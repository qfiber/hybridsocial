defmodule Hybridsocial.Federation.CircuitBreaker do
  @moduledoc """
  Per-domain delivery circuit breaker.

  A persistently-dead remote instance (DNS gone, dead TLS cert, connection
  refused) used to get a fresh delivery attempt for *every* activity we
  fanned out to it — hundreds of pointless DNS/TLS/connect attempts per dead
  host. This trips a breaker after `@threshold` consecutive **connection-level**
  failures and then skips delivery until `circuit_reopen_at`, at which point a
  single probe is allowed to recover.

  Only connection-level failures (`:hard`) trip the breaker — those mean the
  instance is *down*. An HTTP status error (`:soft`, e.g. a 500 on one Delete
  or a 404 for a deactivated user) means the server is *up* and answering, so
  it must NOT open the circuit for the whole domain.

  State lives on `remote_instances` (`consecutive_failures`,
  `unreachable_since`, `circuit_reopen_at`).
  """
  # `only: [from: 2]` — a bare import would shadow this module's own
  # private `update/2` with Ecto.Query's macro of the same name.
  import Ecto.Query, only: [from: 2]
  require Logger

  alias Hybridsocial.Federation.{ActivityMapper, RemoteInstance}
  alias Hybridsocial.Repo

  # Consecutive hard failures before the circuit opens.
  @threshold 5
  # Escalating re-probe backoff once open, indexed by (failures - threshold).
  @reopen_backoff_seconds [3_600, 21_600, 86_400, 259_200]

  @typedoc "Outcome category for a single delivery attempt."
  @type category :: :ok | :soft | :hard

  @doc """
  Whether we should attempt delivery to this inbox right now.

  Returns `true` when the circuit is closed, or open-but-due-for-a-probe
  (`circuit_reopen_at` has passed). Returns `false` while the circuit is
  open and the next probe time is still in the future, and always for a
  domain an admin has disabled delivery to (`delivery_disabled_at`) —
  that one never re-probes. Unknown/malformed inboxes always return
  `true` (fail open — never block a real delivery on a breaker bug).
  """
  @spec allow?(String.t()) :: boolean()
  def allow?(inbox_url) do
    case domain(inbox_url) do
      nil ->
        true

      domain ->
        case Repo.get_by(RemoteInstance, domain: domain) do
          # Admin kill switch wins over the breaker: no probe, ever.
          %RemoteInstance{delivery_disabled_at: %DateTime{}} ->
            false

          %RemoteInstance{circuit_reopen_at: %DateTime{} = reopen} ->
            # Allow once now >= reopen (half-open probe).
            DateTime.compare(now(), reopen) != :lt

          _ ->
            true
        end
    end
  end

  @doc """
  Permanently stop delivering to `domain`. Unlike the breaker's open
  state this never re-probes on its own — it stands until an admin
  calls `enable_delivery/1`. For peers that are gone for good, where
  every retry is a guaranteed timeout and a fresh dead-letter row.

  Does not touch inbound: use an instance policy for that.
  """
  @spec disable_delivery(String.t(), keyword()) :: :ok
  def disable_delivery(domain, opts \\ []) when is_binary(domain) do
    domain = String.downcase(domain)

    Logger.warning("[circuit] delivery to #{domain} disabled by admin")

    upsert(domain, %{
      delivery_disabled_at: now(),
      delivery_disabled_reason: Keyword.get(opts, :reason),
      delivery_disabled_by: Keyword.get(opts, :admin_id)
    })
  end

  @doc """
  Resume delivering to `domain`, clearing the kill switch and the
  breaker state with it so the next activity gets a real attempt
  instead of landing mid-backoff.
  """
  @spec enable_delivery(String.t()) :: :ok
  def enable_delivery(domain) when is_binary(domain) do
    domain = String.downcase(domain)

    Logger.info("[circuit] delivery to #{domain} re-enabled by admin")

    upsert(domain, %{
      delivery_disabled_at: nil,
      delivery_disabled_reason: nil,
      delivery_disabled_by: nil,
      consecutive_failures: 0,
      unreachable_since: nil,
      circuit_reopen_at: nil
    })
  end

  @doc "Whether outbound delivery to this domain is disabled."
  @spec delivery_disabled?(String.t()) :: boolean()
  def delivery_disabled?(domain) when is_binary(domain) do
    MapSet.member?(disabled_domains(), String.downcase(domain))
  end

  @doc """
  Domains we won't attempt right now: disabled by an admin, or with an
  open circuit whose next probe isn't due yet. The same answer `allow?/1`
  gives per inbox, for a whole fan-out in one query.
  """
  @spec blocked_domains() :: MapSet.t()
  def blocked_domains do
    now = now()

    from(r in RemoteInstance,
      where:
        not is_nil(r.delivery_disabled_at) or
          (not is_nil(r.circuit_reopen_at) and r.circuit_reopen_at > ^now),
      select: r.domain
    )
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  The set of domains with delivery disabled. The retry sweep reads it
  to leave their parked rows alone.
  """
  @spec disabled_domains() :: MapSet.t()
  def disabled_domains do
    from(r in RemoteInstance,
      where: not is_nil(r.delivery_disabled_at),
      select: r.domain
    )
    |> Repo.all()
    |> MapSet.new()
  end

  @doc "Disabled peers with their reason, for the admin UI."
  @spec list_disabled() :: [map()]
  def list_disabled do
    from(r in RemoteInstance,
      where: not is_nil(r.delivery_disabled_at),
      order_by: [desc: r.delivery_disabled_at],
      select: %{
        domain: r.domain,
        disabled_at: r.delivery_disabled_at,
        reason: r.delivery_disabled_reason,
        software: r.software
      }
    )
    |> Repo.all()
  end

  @doc """
  Record the outcome of a delivery attempt and update the breaker.

    * `:ok`   — success: reset failures, close the circuit.
    * `:soft` — HTTP status error: server is up, leave the circuit alone.
    * `:hard` — connection error: count it; open the circuit at the threshold.
  """
  @spec record_result(String.t(), category()) :: :ok
  def record_result(inbox_url, category) do
    case domain(inbox_url) do
      nil -> :ok
      domain -> update(domain, category)
    end
  end

  # --- internal ---

  defp update(_domain, :soft), do: :ok

  defp update(domain, :ok) do
    case Repo.get_by(RemoteInstance, domain: domain) do
      %RemoteInstance{} = inst
      when inst.consecutive_failures > 0 or inst.circuit_reopen_at != nil ->
        if inst.circuit_reopen_at do
          Logger.info("[circuit] #{domain} recovered — closing circuit")
        end

        upsert(domain, %{consecutive_failures: 0, unreachable_since: nil, circuit_reopen_at: nil})

      _ ->
        :ok
    end
  end

  defp update(domain, :hard) do
    inst = Repo.get_by(RemoteInstance, domain: domain)
    fails = ((inst && inst.consecutive_failures) || 0) + 1

    attrs =
      if fails >= @threshold do
        reopen = DateTime.add(now(), backoff(fails), :second)
        since = (inst && inst.unreachable_since) || now()

        # Log only on the transition into "open" so we don't spam every probe.
        if is_nil(inst) or is_nil(inst.circuit_reopen_at) do
          Logger.warning(
            "[circuit] #{domain} opened after #{fails} consecutive connection failures; " <>
              "next probe at #{DateTime.to_iso8601(reopen)}"
          )
        end

        %{consecutive_failures: fails, unreachable_since: since, circuit_reopen_at: reopen}
      else
        %{consecutive_failures: fails}
      end

    upsert(domain, attrs)
  end

  # Backoff grows with how long the instance has been failing: 1h, 6h, 24h,
  # then 72h for anything further out.
  defp backoff(fails) do
    idx = min(fails - @threshold, length(@reopen_backoff_seconds) - 1)
    Enum.at(@reopen_backoff_seconds, max(idx, 0))
  end

  defp upsert(domain, attrs) do
    case Repo.get_by(RemoteInstance, domain: domain) do
      nil ->
        %RemoteInstance{}
        |> RemoteInstance.changeset(Map.put(attrs, :domain, domain))
        |> Repo.insert(on_conflict: {:replace, Map.keys(attrs)}, conflict_target: :domain)

      inst ->
        inst |> RemoteInstance.changeset(attrs) |> Repo.update()
    end

    :ok
  end

  defp domain(inbox_url), do: ActivityMapper.extract_domain(inbox_url)

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end
