defmodule Hybridsocial.Media.MediaProxyCache do
  @moduledoc """
  On-disk LRU cache for federated media bytes.

  The Phase 1 proxy fetched the remote URL on every request — fine
  for correctness, terrible for bandwidth. This module sits in front
  of that path: lookup → on hit, serve from local disk; on miss,
  fetch happens at the controller and we persist the result for
  next time.

  Storage layout: each entry is a single file at
  `<uploads_dir>/proxy_cache/<sha256-prefix>/<sha256>` where
  sha256-prefix is the first two hex chars of the URL hash. Keeps
  any one directory under ~256 entries even at million-entry scale.

  Lifetime is governed by two configurable knobs:
    * `media_proxy_cache_ttl_days` (default 7) — after this many
      days without a hit, the entry is dropped.
    * `media_proxy_cache_max_bytes` (default 5 GB) — once total
      cache size exceeds this, oldest-accessed entries are
      dropped until under the cap.

  Both knobs apply at the next eviction tick (run hourly by
  `Hybridsocial.Media.MediaProxyCache.Worker`). Manual eviction by
  domain is also exposed for the admin "instance suspended" flow.
  """
  import Ecto.Query

  alias Hybridsocial.Config
  alias Hybridsocial.Media.Backends.Local
  alias Hybridsocial.Repo

  use Ecto.Schema

  @primary_key {:url_hash, :string, autogenerate: false}
  schema "media_proxy_cache" do
    field :remote_url, :string
    field :remote_origin_domain, :string
    field :content_type, :string
    field :byte_size, :integer
    field :storage_path, :string
    field :fetched_at, :utc_datetime_usec
    field :last_accessed_at, :utc_datetime_usec
  end

  @doc "Returns true when the cache layer is enabled in instance config."
  def enabled? do
    Config.get("media_proxy_cache_enabled", true) == true
  end

  @doc "TTL in days for cache entries (idle eviction threshold)."
  def ttl_days, do: Config.get("media_proxy_cache_ttl_days", 7)

  @doc "Total cache size cap in bytes (LRU eviction threshold)."
  def max_bytes, do: Config.get("media_proxy_cache_max_bytes", 5 * 1024 * 1024 * 1024)

  @doc """
  Look up a cached entry by remote URL. On hit, returns the file
  path + content type so the caller can `send_file`. On miss,
  returns `:miss` and the caller should fetch + `store/3`.
  """
  def lookup(remote_url) when is_binary(remote_url) do
    if enabled?() do
      hash = hash_url(remote_url)

      case Repo.get(__MODULE__, hash) do
        nil ->
          :miss

        entry ->
          path = absolute_path(entry.storage_path)

          if File.exists?(path) do
            {:hit, %{path: path, content_type: entry.content_type, hash: hash}}
          else
            # DB row references a file that's been deleted out from
            # under us (manual cleanup, disk repair). Treat as miss
            # and prune the orphan row.
            Repo.delete(entry)
            :miss
          end
      end
    else
      :miss
    end
  end

  def lookup(_), do: :miss

  @doc """
  Store a fetched body under its URL hash. Idempotent — concurrent
  stores of the same URL just last-write-wins on both the file and
  the DB row.
  """
  def store(remote_url, body, content_type)
      when is_binary(remote_url) and is_binary(body) and is_binary(content_type) do
    if enabled?() do
      hash = hash_url(remote_url)
      relative = path_for(hash)
      absolute = absolute_path(relative)

      with :ok <- File.mkdir_p(Path.dirname(absolute)),
           :ok <- File.write(absolute, body),
           {:ok, _entry} <- upsert_entry(hash, remote_url, content_type, body, relative) do
        :ok
      else
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end

  def store(_, _, _), do: :ok

  @doc """
  Promote an already-written file (typically a streaming-download
  tmp file) into the cache. Renames the source into the canonical
  cache layout and writes the DB row.

  On success returns `{:ok, %{path: path, hash: hash}}` so the
  caller can `send_file` directly. The source file is consumed —
  callers must not use it afterwards.
  """
  def store_path(remote_url, source_path, content_type, byte_size)
      when is_binary(remote_url) and is_binary(source_path) and is_binary(content_type) and
             is_integer(byte_size) do
    if enabled?() do
      hash = hash_url(remote_url)
      relative = path_for(hash)
      absolute = absolute_path(relative)

      with :ok <- File.mkdir_p(Path.dirname(absolute)),
           :ok <- rename_or_copy(source_path, absolute),
           {:ok, _entry} <-
             upsert_entry_meta(hash, remote_url, content_type, byte_size, relative) do
        {:ok, %{path: absolute, hash: hash}}
      else
        {:error, reason} ->
          File.rm(source_path)
          {:error, reason}
      end
    else
      # Callers check `enabled?/0` first; this only runs if the setting
      # flips mid-request. An explicit error beats a bare `:ok` the
      # caller can't serve from (the source file is gone).
      File.rm(source_path)
      {:error, :cache_disabled}
    end
  end

  # File.rename/2 is atomic on the same filesystem but fails with
  # :exdev if /tmp lives on a different device than the uploads
  # volume. Fall back to copy+delete in that case.
  defp rename_or_copy(source, dest) do
    case File.rename(source, dest) do
      :ok ->
        :ok

      {:error, :exdev} ->
        with :ok <- File.cp(source, dest) do
          File.rm(source)
          :ok
        end

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Bump `last_accessed_at` so this entry survives the next LRU
  eviction. Best-effort — failures are ignored since stale
  timestamps only cost us a re-fetch later.
  """
  def touch(hash) when is_binary(hash) do
    now = DateTime.utc_now()

    from(e in __MODULE__, where: e.url_hash == ^hash)
    |> Repo.update_all(set: [last_accessed_at: now])

    :ok
  rescue
    _ -> :ok
  end

  @doc """
  Drop every cached entry from the given remote instance. Use when
  an instance is freshly suspended / `block_media`'d so its content
  doesn't continue serving from cache.
  """
  def evict_by_domain(domain) when is_binary(domain) do
    entries =
      Repo.all(from(e in __MODULE__, where: e.remote_origin_domain == ^domain))

    Enum.each(entries, &delete_entry/1)
    {:ok, length(entries)}
  end

  @doc """
  Drop entries whose `last_accessed_at` is older than the configured
  TTL. Returns the count evicted.
  """
  def evict_expired(now \\ DateTime.utc_now()) do
    cutoff = DateTime.add(now, -ttl_days() * 24 * 3600, :second)

    entries =
      Repo.all(from(e in __MODULE__, where: e.last_accessed_at < ^cutoff))

    Enum.each(entries, &delete_entry/1)
    {:ok, length(entries)}
  end

  @doc """
  If total cache size exceeds `max_bytes`, drop oldest-accessed
  entries until under the cap. Returns the count evicted.
  """
  def evict_lru do
    total = total_bytes()
    cap = max_bytes()

    if total > cap do
      to_free = total - cap
      free_lru(to_free, 0)
    else
      {:ok, 0}
    end
  end

  @doc "Total bytes occupied by cached files (per the DB — disk may differ)."
  def total_bytes do
    # Postgres SUM() over bigint returns a Decimal; normalize to a
    # plain integer so callers can do arithmetic without surprises.
    Repo.one(from(e in __MODULE__, select: coalesce(sum(e.byte_size), 0)))
    |> to_integer()
  end

  defp to_integer(nil), do: 0
  defp to_integer(n) when is_integer(n), do: n
  defp to_integer(%Decimal{} = d), do: Decimal.to_integer(d)

  # --- Internals ----------------------------------------------------------

  defp free_lru(target_bytes, freed) when freed >= target_bytes, do: {:ok, freed}

  defp free_lru(target_bytes, freed) do
    # Pull the oldest 50 at a time so a 100GB overrun doesn't
    # materialize the whole table.
    batch =
      Repo.all(from(e in __MODULE__, order_by: [asc: e.last_accessed_at], limit: 50))

    case batch do
      [] ->
        {:ok, freed}

      entries ->
        new_freed =
          Enum.reduce_while(entries, freed, fn entry, acc ->
            delete_entry(entry)
            new_acc = acc + (entry.byte_size || 0)
            if new_acc >= target_bytes, do: {:halt, new_acc}, else: {:cont, new_acc}
          end)

        if new_freed >= target_bytes do
          {:ok, new_freed}
        else
          free_lru(target_bytes, new_freed)
        end
    end
  end

  defp delete_entry(entry) do
    case File.rm(absolute_path(entry.storage_path)) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      _ -> :ok
    end

    Repo.delete(entry)
  end

  defp upsert_entry(hash, remote_url, content_type, body, storage_path) do
    upsert_entry_meta(hash, remote_url, content_type, byte_size(body), storage_path)
  end

  defp upsert_entry_meta(hash, remote_url, content_type, byte_size, storage_path) do
    now = DateTime.utc_now()
    domain = URI.parse(remote_url).host || "unknown"

    attrs = %{
      url_hash: hash,
      remote_url: remote_url,
      remote_origin_domain: domain,
      content_type: content_type,
      byte_size: byte_size,
      storage_path: storage_path,
      fetched_at: now,
      last_accessed_at: now
    }

    %__MODULE__{}
    |> Ecto.Changeset.cast(attrs, Map.keys(attrs))
    |> Repo.insert(
      on_conflict: {:replace, [:byte_size, :storage_path, :fetched_at, :last_accessed_at]},
      conflict_target: :url_hash
    )
  end

  defp hash_url(url) do
    :crypto.hash(:sha256, url) |> Base.encode16(case: :lower)
  end

  defp path_for(hash) do
    Path.join(["proxy_cache", String.slice(hash, 0, 2), hash])
  end

  defp absolute_path(relative_path) do
    Path.join(Local.uploads_dir(), relative_path)
  end
end
