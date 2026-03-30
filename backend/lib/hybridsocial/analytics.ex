defmodule Hybridsocial.Analytics do
  @moduledoc """
  Analytics data for admin charts — user growth, post volume, federation activity,
  storage usage, engagement metrics. All queries are time-bucketed by day.
  """

  import Ecto.Query
  alias Hybridsocial.Repo

  @doc "User registrations per day for the last N days."
  def user_growth(days \\ 30) do
    cutoff = Date.add(Date.utc_today(), -days)

    from(u in "users",
      where: fragment("?::date >= ?", u.inserted_at, ^cutoff),
      group_by: fragment("?::date", u.inserted_at),
      select: %{date: fragment("?::date", u.inserted_at), count: count(u.identity_id)},
      order_by: fragment("?::date", u.inserted_at)
    )
    |> Repo.all()
  end

  @doc "Posts created per day for the last N days."
  def post_volume(days \\ 30) do
    cutoff = Date.add(Date.utc_today(), -days)

    from(p in "posts",
      where: fragment("?::date >= ?", p.inserted_at, ^cutoff) and is_nil(p.deleted_at),
      group_by: fragment("?::date", p.inserted_at),
      select: %{date: fragment("?::date", p.inserted_at), count: count(p.id)},
      order_by: fragment("?::date", p.inserted_at)
    )
    |> Repo.all()
  end

  @doc "Active users per day (users who posted) for the last N days."
  def active_users(days \\ 30) do
    cutoff = Date.add(Date.utc_today(), -days)

    from(p in "posts",
      where: fragment("?::date >= ?", p.inserted_at, ^cutoff) and is_nil(p.deleted_at),
      group_by: fragment("?::date", p.inserted_at),
      select: %{date: fragment("?::date", p.inserted_at), count: count(p.identity_id, :distinct)},
      order_by: fragment("?::date", p.inserted_at)
    )
    |> Repo.all()
  end

  @doc "Reactions per day."
  def reactions_per_day(days \\ 30) do
    cutoff = Date.add(Date.utc_today(), -days)

    from(r in "reactions",
      where: fragment("?::date >= ?", r.inserted_at, ^cutoff),
      group_by: fragment("?::date", r.inserted_at),
      select: %{date: fragment("?::date", r.inserted_at), count: count(r.id)},
      order_by: fragment("?::date", r.inserted_at)
    )
    |> Repo.all()
  end

  @doc "New follows per day."
  def follows_per_day(days \\ 30) do
    cutoff = Date.add(Date.utc_today(), -days)

    from(f in "follows",
      where: fragment("?::date >= ?", f.inserted_at, ^cutoff),
      group_by: fragment("?::date", f.inserted_at),
      select: %{date: fragment("?::date", f.inserted_at), count: count(f.id)},
      order_by: fragment("?::date", f.inserted_at)
    )
    |> Repo.all()
  end

  @doc "Storage usage summary."
  def storage_stats do
    media = from(m in "media", select: %{count: count(m.id), total_bytes: sum(m.file_size)}) |> Repo.one()
    %{
      media_count: media[:count] || 0,
      total_bytes: media[:total_bytes] || 0
    }
  end

  @doc "Federation stats — remote actors cached."
  def federation_stats do
    remote_actors = from(ra in "remote_actors", select: count(ra.id)) |> Repo.one() || 0
    remote_identities =
      from(i in "identities",
        where: not is_nil(i.ap_actor_url) and i.ap_actor_url != "",
        select: count(i.id)
      ) |> Repo.one() || 0

    %{
      remote_actors: remote_actors,
      remote_identities: remote_identities
    }
  end

  @doc "Summary stats for the dashboard."
  def summary do
    total_users = from(u in "users", select: count(u.identity_id)) |> Repo.one() || 0
    total_posts = from(p in "posts", where: is_nil(p.deleted_at), select: count(p.id)) |> Repo.one() || 0
    total_reactions = from(r in "reactions", select: count(r.id)) |> Repo.one() || 0

    today = Date.utc_today()
    posts_today =
      from(p in "posts",
        where: fragment("?::date = ?", p.inserted_at, ^today) and is_nil(p.deleted_at),
        select: count(p.id)
      ) |> Repo.one() || 0

    registrations_today =
      from(u in "users",
        where: fragment("?::date = ?", u.inserted_at, ^today),
        select: count(u.identity_id)
      ) |> Repo.one() || 0

    %{
      total_users: total_users,
      total_posts: total_posts,
      total_reactions: total_reactions,
      posts_today: posts_today,
      registrations_today: registrations_today,
      storage: storage_stats(),
      federation: federation_stats()
    }
  end
end
