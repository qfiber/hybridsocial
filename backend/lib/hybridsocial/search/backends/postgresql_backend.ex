defmodule Hybridsocial.Search.Backends.PostgresqlBackend do
  @moduledoc """
  PostgreSQL search backend using tsvector/tsquery full-text search and ILIKE.

  This is the default and fallback backend that requires no external services.
  """

  @behaviour Hybridsocial.Search.Backend

  import Ecto.Query

  alias Hybridsocial.Repo
  alias Hybridsocial.Accounts.Identity
  alias Hybridsocial.Social.{Post, Hashtag}
  alias Hybridsocial.Groups.Group

  @default_limit 20
  @max_limit 40

  @impl true
  def search_accounts(query, opts) do
    limit = parse_limit(opts)
    offset = parse_offset(opts)
    tsquery = prefix_tsquery(query)
    ilike_pattern = "#{escape_like(query)}%"

    results =
      Identity
      |> where([i], is_nil(i.deleted_at))
      |> where([i], i.is_suspended == false)
      |> where(
        [i],
        fragment("? @@ to_tsquery('english', ?)", i.search_vector, ^tsquery) or
          ilike(i.handle, ^ilike_pattern)
      )
      |> order_by([i], asc: i.handle)
      |> limit(^limit)
      |> offset(^offset)
      |> Repo.all()

    {:ok, results}
  end

  @impl true
  def search_posts(query, viewer_id, opts) do
    limit = parse_limit(opts)
    offset = parse_offset(opts)
    account_id = Keyword.get(opts, :account_id)
    tsquery = prefix_tsquery(query)

    results =
      Post
      |> where([p], is_nil(p.deleted_at))
      |> where([p], fragment("? @@ to_tsquery('english', ?)", p.search_vector, ^tsquery))
      |> apply_visibility_filter(viewer_id)
      |> apply_account_filter(account_id)
      |> order_by([p], desc: p.published_at)
      |> limit(^limit)
      |> offset(^offset)
      |> Repo.all()
      |> Repo.preload(:identity)

    {:ok, results}
  end

  @impl true
  def search_hashtags(query, opts) do
    limit = parse_limit(opts)
    offset = parse_offset(opts)
    ilike_pattern = "%#{escape_like(query)}%"

    results =
      Hashtag
      |> where([h], ilike(h.name, ^ilike_pattern))
      |> order_by([h], desc: h.usage_count)
      |> limit(^limit)
      |> offset(^offset)
      |> Repo.all()

    {:ok, results}
  end

  @impl true
  def search_groups(query, opts) do
    limit = parse_limit(opts)
    offset = parse_offset(opts)
    viewer_id = Keyword.get(opts, :viewer_id)
    ilike_pattern = "%#{escape_like(query)}%"

    results =
      Group
      |> where([g], is_nil(g.deleted_at))
      |> where([g], ilike(g.name, ^ilike_pattern) or ilike(g.description, ^ilike_pattern))
      |> apply_group_visibility_filter(viewer_id)
      |> order_by([g], desc: g.member_count)
      |> limit(^limit)
      |> offset(^offset)
      |> Repo.all()

    {:ok, results}
  end

  @impl true
  def healthy?, do: true

  @impl true
  def name, do: "PostgreSQL"

  # --- Private helpers ---

  defp apply_visibility_filter(query, nil) do
    where(query, [p], p.visibility == "public")
  end

  defp apply_visibility_filter(query, viewer_id) do
    where(query, [p], p.visibility == "public" or p.identity_id == type(^viewer_id, Ecto.UUID))
  end

  defp apply_account_filter(query, nil), do: query

  defp apply_account_filter(query, account_id) do
    where(query, [p], p.identity_id == type(^account_id, Ecto.UUID))
  end

  defp apply_group_visibility_filter(query, nil) do
    where(query, [g], g.visibility in [:public, :private])
  end

  defp apply_group_visibility_filter(query, viewer_id) do
    where(
      query,
      [g],
      g.visibility in [:public, :private] or
        g.id in subquery(
          from(gm in "group_members",
            where: gm.identity_id == type(^viewer_id, Ecto.UUID) and gm.status == "approved",
            select: gm.group_id
          )
        )
    )
  end

  defp prefix_tsquery(sanitized) do
    sanitized
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(&"#{&1}:*")
    |> Enum.join(" & ")
  end

  defp escape_like(string) do
    string
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  defp parse_limit(opts) do
    opts
    |> Keyword.get(:limit, @default_limit)
    |> min(@max_limit)
    |> max(1)
  end

  defp parse_offset(opts) do
    opts
    |> Keyword.get(:offset, 0)
    |> max(0)
  end
end
