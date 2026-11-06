defmodule Hybridsocial.Trending.ExploreFeed do
  @moduledoc """
  Explore's Trending tab: one feed blending engaged posts, the top posts of
  trending hashtags and the best recent post of trending accounts, from both
  this instance and the wider fediverse.

  ## Why it is precomputed

  The clients page by the last post's id. A ranking computed on read shifts
  between requests, so pages would repeat and skip posts. `refresh/1` writes the
  order to `trending_feed_entries`, and `list/1` keysets over the stored slot.

  ## Ranking

    * Engagement counts distinct accounts rather than the denormalized counters.
      An author's own engagement, moderated accounts and anything past a
      per-domain cap are ignored, so neither sockpuppets nor a single remote
      server can buy a place in the feed.
    * `score = ln(1 + engagement + bonus) + ln(2) * published_unix / half_life`.
      This is exponential decay written in log space, so the order changes only
      when engagement does, not merely because time passed.
    * Each further post by an author loses `author_penalty`, across the whole
      feed. A penalty rather than a cap, so a quiet instance keeps its content.
    * Local and remote posts are ranked separately and interleaved by
      `local_share`. Their counters aren't comparable (we only see the remote
      engagement that gets delivered to us), and remote posts outnumber local
      ones by far, so one ranking would bury local posts. When one side runs out
      the other fills the feed.

  Moderation and viewer filters run again in `list/1`, so hiding a post or
  blocking an author applies at once rather than on the next refresh, and pages
  stay full.

  Every tunable is an `explore_trending_*` setting; see `settings/0`.
  """
  import Ecto.Query

  alias Hybridsocial.Accounts.Identity
  alias Hybridsocial.Config
  alias Hybridsocial.Feeds.Visibility
  alias Hybridsocial.Repo
  alias Hybridsocial.Social.{Boost, Follow, Post, Reaction}
  alias Hybridsocial.Trending
  alias Hybridsocial.Trending.FeedEntry

  @default_limit 20
  @max_limit 40
  @insert_batch 500

  @reaction_weight 1.0
  @no_engagement %{weight: 0.0, unique: 0, engagers: MapSet.new()}

  # `{setting suffix, default}`. Local posts get a longer window and a lower bar
  # because a quiet instance has far fewer of them.
  @defaults [
    window_hours_local: 168,
    window_hours_remote: 72,
    half_life_hours: 24,
    local_share: 0.25,
    boost_weight: 2.0,
    reply_weight: 1.5,
    min_engagement_local: 1,
    min_engagement_remote: 3,
    min_fill_local: 20,
    max_engagers_per_domain: 10,
    max_candidates: 2000,
    max_entries: 500,
    top_tags: 20,
    posts_per_tag: 3,
    # Bonuses are worth this many engagement points. A tag's or account's post
    # usually has modest engagement of its own, so a small bonus would leave
    # those sources at the very bottom of the feed, where nobody sees them.
    tag_bonus: 5.0,
    tag_min_engagement: 1,
    max_tags_per_post: 8,
    top_accounts: 20,
    account_bonus: 3.0,
    account_min_engagement: 3,
    author_penalty: 1.5,
    retired_ttl_hours: 6
  ]

  @doc "The current tunables, as numbers, from the `explore_trending_*` settings."
  def settings do
    Map.new(@defaults, fn {key, default} ->
      {key, numeric_setting("explore_trending_#{key}", default)}
    end)
  end

  defp numeric_setting(key, default) do
    case Config.get(key, default) do
      value when is_number(value) ->
        value

      value when is_binary(value) ->
        case Float.parse(value) do
          {parsed, _} -> parsed
          :error -> default
        end

      _ ->
        default
    end
  end

  # --- Read ---

  @doc """
  One page of the feed, as `{post, reason}` tuples. `reason` is nil, or
  `%{type: "tag", tag: name}` or `%{type: "account"}`.

  ## Options

    * `:viewer_id`  - applies the viewer's blocks, mutes and domain blocks.
      Without a viewer, sensitive posts are left out too.
    * `:local_only` - only this instance's posts
    * `:max_id`     - the last post of the previous page
    * `:limit`      - page size
  """
  def list(opts \\ []) do
    case resolve_cursor(Keyword.get(opts, :max_id)) do
      :unknown ->
        # An unknown cursor must not restart the feed from the top: the client
        # would append page one again and scroll forever.
        []

      cursor ->
        rows = opts |> page_query(cursor) |> Repo.all()
        posts = rows |> Enum.map(&elem(&1, 0)) |> Repo.preload([:identity, :quote])

        posts
        |> Enum.zip(rows)
        |> Enum.map(fn {post, {_post, entry}} -> {post, reason(entry)} end)
    end
  end

  @doc """
  Of the given authors, the ones the viewer needn't be offered a follow button
  for: already followed, requested, or the viewer themselves.
  """
  def followed_author_ids(viewer_id, author_ids) do
    followed =
      from(f in Follow,
        where:
          f.follower_id == ^viewer_id and f.followee_id in ^author_ids and
            f.status in [:accepted, :pending],
        select: f.followee_id
      )
      |> Repo.all()

    MapSet.new([viewer_id | followed])
  end

  defp page_query(opts, cursor) do
    viewer_id = Keyword.get(opts, :viewer_id)
    limit = opts |> Keyword.get(:limit, @default_limit) |> min(@max_limit) |> max(1)

    from(p in Post,
      join: e in FeedEntry,
      on: e.post_id == p.id,
      join: i in Identity,
      on: i.id == p.identity_id,
      left_join: q in Post,
      on: q.id == p.quote_id,
      where: e.active == true,
      where: p.visibility == "public" and is_nil(p.deleted_at) and is_nil(p.hidden_at),
      # The serializer embeds a quote as-is, and this feed would amplify it to
      # everyone, so don't carry a quote that isn't itself fit to be public.
      where:
        is_nil(p.quote_id) or
          (q.visibility == "public" and is_nil(q.deleted_at) and is_nil(q.hidden_at) and
             q.identity_id not in subquery(Visibility.publicly_hidden_author_ids())),
      order_by: [asc: e.slot, asc: e.post_id],
      limit: ^limit,
      select: {p, e}
    )
    |> Visibility.apply_suspension_filter()
    |> Visibility.apply_silence_filter()
    |> Visibility.apply_blocked_hashtag_filter()
    |> Visibility.apply_shadow_ban_filter(viewer_id)
    |> Visibility.apply_block_filter(viewer_id)
    |> Visibility.apply_mute_filter(viewer_id)
    |> maybe_filter_domain_blocks(viewer_id)
    |> maybe_filter_sensitive(viewer_id)
    |> maybe_local_only(Keyword.get(opts, :local_only, false))
    |> apply_cursor(cursor)
  end

  defp maybe_filter_domain_blocks(query, nil), do: query

  # Same derivation as `Social.Streams`: identities carry no domain column.
  defp maybe_filter_domain_blocks(query, viewer_id) do
    where(
      query,
      [p, e, i],
      i.is_local == true or is_nil(i.ap_actor_url) or
        not fragment(
          "EXISTS (SELECT 1 FROM user_domain_blocks udb WHERE udb.identity_id = ? AND udb.domain = lower(split_part(split_part(?, '/', 3), ':', 1)))",
          type(^viewer_id, Ecto.UUID),
          i.ap_actor_url
        )
    )
  end

  defp maybe_filter_sensitive(query, nil), do: where(query, [p], p.sensitive == false)
  defp maybe_filter_sensitive(query, _viewer_id), do: query

  defp maybe_local_only(query, true), do: where(query, [p, e], e.is_local == true)
  defp maybe_local_only(query, _), do: query

  defp apply_cursor(query, nil), do: query

  defp apply_cursor(query, {slot, post_id}) do
    where(
      query,
      [p, e],
      fragment("(?, ?) > (?, ?)", e.slot, e.post_id, ^slot, type(^post_id, Ecto.UUID))
    )
  end

  defp resolve_cursor(nil), do: nil

  # Retired rows resolve too, so a refresh mid-scroll doesn't end the feed. Their
  # slot is approximate against the new order; the client dedupes any overlap.
  defp resolve_cursor(max_id) do
    with {:ok, id} <- Ecto.UUID.cast(max_id),
         %FeedEntry{} = entry <- Repo.get(FeedEntry, id) do
      {entry.slot, entry.post_id}
    else
      _ -> :unknown
    end
  end

  defp reason(%FeedEntry{reason_type: "tag", reason_tag: tag}), do: %{type: "tag", tag: tag}
  defp reason(%FeedEntry{reason_type: "account"}), do: %{type: "account"}
  defp reason(_entry), do: nil

  # --- Refresh ---

  @doc "Recomputes the feed and swaps it in atomically, so readers never see it empty."
  def refresh(now \\ DateTime.utc_now()) do
    now = DateTime.truncate(now, :microsecond)
    settings = settings()

    candidates = candidates(true, settings, now) ++ candidates(false, settings, now)
    engagement = engagement(candidates, settings)
    scored = Enum.map(candidates, &score(&1, engagement, settings))

    selected =
      scored
      |> select_entries(settings)
      |> fill_local(settings, now)

    selected
    |> slot_entries(settings)
    |> swap(settings, now)

    :ok
  end

  defp candidates(local?, settings, now) do
    window = if local?, do: settings.window_hours_local, else: settings.window_hours_remote

    eligible_posts(local?, cutoff(window, now), now)
    # Only a coarse pre-filter: these counters aren't trusted for ranking.
    |> where([p], p.reaction_count + p.boost_count + p.reply_count >= 1)
    |> order_by([p], desc: p.reaction_count + p.boost_count * 2 + p.reply_count, desc: p.id)
    |> limit(^trunc(settings.max_candidates))
    |> candidate_select()
    |> Repo.all()
  end

  defp eligible_posts(local?, cutoff, now) do
    from(p in Post,
      join: i in Identity,
      on: i.id == p.identity_id,
      where: p.visibility == "public" and is_nil(p.deleted_at) and is_nil(p.hidden_at),
      where: is_nil(p.parent_id) and is_nil(p.parent_ap_id),
      # A remote `published` is whatever the sender claims. A future date must
      # not read as maximally fresh, and a backfilled old post isn't new.
      where: p.published_at >= ^cutoff and p.published_at <= ^now,
      where: i.is_local == ^local?,
      where: p.identity_id not in subquery(Visibility.publicly_hidden_author_ids())
    )
    |> Visibility.apply_blocked_hashtag_filter()
  end

  defp candidate_select(query) do
    select(query, [p, i], %{
      id: p.id,
      identity_id: p.identity_id,
      published_at: p.published_at,
      is_local: i.is_local,
      account_type: i.type,
      discoverable: i.discoverable
    })
  end

  defp cutoff(hours, now), do: DateTime.add(now, -trunc(hours * 3600), :second)

  # %{post_id => %{weight: weighted engagement, unique: distinct accounts}}
  defp engagement(candidates, settings) do
    authors = Map.new(candidates, &{&1.id, &1.identity_id})
    post_ids = Map.keys(authors)

    weights = %{
      reaction: @reaction_weight,
      boost: settings.boost_weight,
      reply: settings.reply_weight
    }

    (engagers(Reaction, post_ids, :reaction) ++
       engagers(Boost, post_ids, :boost) ++ engagers(:reply, post_ids, :reply))
    |> Enum.reject(fn row -> row.identity_id == authors[row.post_id] end)
    |> Enum.group_by(& &1.post_id)
    |> Map.new(fn {post_id, rows} ->
      {post_id, post_engagement(rows, weights, settings.max_engagers_per_domain)}
    end)
  end

  defp post_engagement(rows, weights, per_domain_cap) do
    counted =
      rows
      |> Enum.uniq_by(& &1.identity_id)
      |> Enum.group_by(& &1.domain)
      |> Enum.flat_map(fn
        # Local accounts aren't capped: registration has its own defences, and
        # no remote server can mint them.
        {nil, engagers} -> engagers
        {_domain, engagers} -> Enum.take(engagers, trunc(per_domain_cap))
      end)
      |> MapSet.new(& &1.identity_id)

    weight =
      rows
      |> Enum.filter(&MapSet.member?(counted, &1.identity_id))
      |> Enum.uniq_by(&{&1.identity_id, &1.kind})
      |> Enum.reduce(0.0, fn row, sum -> sum + weights[row.kind] end)

    %{weight: weight, unique: MapSet.size(counted), engagers: counted}
  end

  defp engagers(_source, [], _kind), do: []

  defp engagers(source, post_ids, kind) do
    engager_source(source, post_ids)
    |> join(:inner, [e], i in Identity, on: i.id == e.identity_id)
    # Once an account is moderated its engagement stops counting, which also
    # unwinds a sockpuppet ring as soon as it is actioned.
    |> where([e], e.identity_id not in subquery(Visibility.publicly_hidden_author_ids()))
    |> select_engager(source)
    |> Repo.all()
    |> Enum.map(&Map.put(&1, :kind, kind))
  end

  defp engager_source(Reaction, post_ids), do: where(Reaction, [r], r.post_id in ^post_ids)

  defp engager_source(Boost, post_ids),
    do: where(Boost, [b], b.post_id in ^post_ids and is_nil(b.deleted_at))

  defp engager_source(:reply, post_ids) do
    where(
      Post,
      [r],
      r.parent_id in ^post_ids and is_nil(r.deleted_at) and is_nil(r.hidden_at)
    )
  end

  defp select_engager(query, :reply) do
    select(query, [r, i], %{
      post_id: r.parent_id,
      identity_id: r.identity_id,
      domain:
        fragment(
          "CASE WHEN ? THEN NULL ELSE lower(split_part(split_part(?, '/', 3), ':', 1)) END",
          i.is_local,
          i.ap_actor_url
        )
    })
  end

  defp select_engager(query, _source) do
    select(query, [e, i], %{
      post_id: e.post_id,
      identity_id: e.identity_id,
      domain:
        fragment(
          "CASE WHEN ? THEN NULL ELSE lower(split_part(split_part(?, '/', 3), ':', 1)) END",
          i.is_local,
          i.ap_actor_url
        )
    })
  end

  defp score(candidate, engagement, settings) do
    stats = Map.get(engagement, candidate.id, @no_engagement)
    candidate |> Map.merge(stats) |> put_score(0.0, settings)
  end

  defp put_score(entry, bonus, settings) do
    half_life = settings.half_life_hours * 3600
    freshness = :math.log(2) * DateTime.to_unix(entry.published_at) / half_life

    Map.put(entry, :score, :math.log(1 + entry.weight + bonus) + freshness)
  end

  # --- Selection ---

  # Union of the three sources, one row per post. A tag explains a post better
  # than an account does, and a post that clears the engagement bar on its own
  # needs no account label.
  defp select_entries(scored, settings) do
    tag_reasons = tag_reasons(scored, settings)
    account_ids = account_post_ids(scored, settings)

    Enum.flat_map(scored, fn entry ->
      tag = tag_reasons[entry.id]
      engaged? = entry.unique >= min_engagement(entry, settings)
      account? = MapSet.member?(account_ids, entry.id)

      cond do
        tag -> [entry |> put_reason("tag", tag) |> put_score(settings.tag_bonus, settings)]
        engaged? -> [put_reason(entry, nil, nil)]
        account? -> [account_entry(entry, settings)]
        true -> []
      end
    end)
  end

  defp account_entry(entry, settings) do
    entry |> put_reason("account", nil) |> put_score(settings.account_bonus, settings)
  end

  defp min_engagement(%{is_local: true}, settings), do: settings.min_engagement_local
  defp min_engagement(%{is_local: false}, settings), do: settings.min_engagement_remote

  defp put_reason(entry, type, tag), do: Map.merge(entry, %{reason_type: type, reason_tag: tag})

  # %{post_id => tag}: the top posts of each trending tag. A post with several
  # keeps its highest-ranked tag.
  defp tag_reasons(scored, settings) do
    names =
      [limit: trunc(settings.top_tags)]
      |> Trending.get_trending_hashtags()
      |> Enum.map(& &1.target_id)

    by_id = Map.new(scored, &{&1.id, &1})
    tagged = tagged_posts(Map.keys(by_id), names, settings)

    Enum.reduce(names, %{}, fn name, reasons ->
      tagged
      |> Map.get(name, [])
      |> Enum.map(&by_id[&1])
      |> Enum.filter(&(&1.unique >= settings.tag_min_engagement))
      |> Enum.sort_by(& &1.score, :desc)
      |> Enum.take(trunc(settings.posts_per_tag))
      |> Enum.reduce(reasons, fn entry, acc -> Map.put_new(acc, entry.id, name) end)
    end)
  end

  # %{tag => [post_id]}, leaving out tag-stuffed posts: a post that lists many
  # tags to ride a trend doesn't get a way in through any of them.
  defp tagged_posts([], _names, _settings), do: %{}
  defp tagged_posts(_post_ids, [], _settings), do: %{}

  defp tagged_posts(post_ids, names, settings) do
    max_tags = trunc(settings.max_tags_per_post)

    stuffed =
      from(ph in "post_hashtags",
        where: ph.post_id in type(^post_ids, {:array, Ecto.UUID}),
        group_by: ph.post_id,
        having: count(ph.hashtag_id) > ^max_tags,
        select: type(ph.post_id, Ecto.UUID)
      )
      |> Repo.all()
      |> MapSet.new()

    from(ph in "post_hashtags",
      join: h in "hashtags",
      on: h.id == ph.hashtag_id,
      where: ph.post_id in type(^post_ids, {:array, Ecto.UUID}) and h.name in ^names,
      select: {h.name, type(ph.post_id, Ecto.UUID)}
    )
    |> Repo.all()
    |> Enum.reject(fn {_name, post_id} -> MapSet.member?(stuffed, post_id) end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  # The best post of each account drawing the most engagement right now. Ranked
  # on this window's engagement alone, so a big dormant account doesn't qualify
  # on its follower count, and only for people who opted into discovery.
  defp account_post_ids(scored, settings) do
    scored
    |> Enum.filter(&(&1.account_type == "user" and &1.discoverable and &1.unique >= 1))
    |> Enum.group_by(& &1.identity_id)
    |> Enum.map(fn {_author, posts} ->
      distinct = posts |> Enum.map(& &1.engagers) |> Enum.reduce(&MapSet.union/2) |> MapSet.size()
      {distinct, Enum.sum_by(posts, & &1.weight), Enum.max_by(posts, & &1.score)}
    end)
    # Distinct people rather than weighted engagement: one puppet's reaction and
    # boost must not add up to a trending account.
    |> Enum.filter(fn {distinct, _total, _best} ->
      distinct >= settings.account_min_engagement
    end)
    |> Enum.sort_by(fn {_distinct, total, _best} -> total end, :desc)
    |> Enum.take(trunc(settings.top_accounts))
    |> MapSet.new(fn {_distinct, _total, best} -> best.id end)
  end

  # On a quiet instance, recent local posts keep the local share from running
  # dry. Remote posts get no such pass: they are plentiful, and anyone can send
  # us an unengaged one.
  defp fill_local(entries, settings, now) do
    missing = trunc(settings.min_fill_local) - Enum.count(entries, & &1.is_local)

    if missing <= 0 do
      entries
    else
      taken = Enum.map(entries, & &1.id)

      fill =
        eligible_posts(true, cutoff(settings.window_hours_local, now), now)
        |> where([p], p.id not in ^taken)
        |> order_by([p], desc: p.published_at, desc: p.id)
        |> limit(^missing)
        |> candidate_select()
        |> Repo.all()
        |> Enum.map(fn candidate ->
          candidate
          |> Map.merge(@no_engagement)
          |> put_score(0.0, settings)
          |> put_reason(nil, nil)
        end)

      entries ++ fill
    end
  end

  # --- Ordering ---

  defp slot_entries(entries, settings) do
    share = settings.local_share |> max(0.0) |> min(1.0)
    penalty = settings.author_penalty
    {local, remote} = Enum.split_with(entries, & &1.is_local)

    (slot_cohort(local, share, penalty) ++ slot_cohort(remote, 1.0 - share, penalty))
    |> Enum.sort_by(&{&1.slot, &1.id})
    |> Enum.take(trunc(settings.max_entries))
  end

  defp slot_cohort(_entries, share, _penalty) when share <= 0, do: []

  # `(rank + 0.5) / share` spreads a cohort evenly: at a 0.25 share its posts land
  # on slots 2, 6, 10... When the other cohort runs out, these simply follow on.
  defp slot_cohort(entries, share, penalty) do
    entries
    |> penalize_repeat_authors(penalty)
    |> Enum.sort_by(& &1.score, :desc)
    |> Enum.with_index()
    |> Enum.map(fn {entry, rank} -> Map.put(entry, :slot, (rank + 0.5) / share) end)
  end

  defp penalize_repeat_authors(entries, penalty) do
    entries
    |> Enum.group_by(& &1.identity_id)
    |> Enum.flat_map(fn {_author, posts} ->
      posts
      |> Enum.sort_by(& &1.score, :desc)
      |> Enum.with_index()
      |> Enum.map(fn {post, repeat} -> %{post | score: post.score - repeat * penalty} end)
    end)
  end

  # --- Write ---

  defp swap(entries, settings, now) do
    rows =
      Enum.map(entries, fn entry ->
        %{
          post_id: entry.id,
          slot: entry.slot,
          score: entry.score,
          is_local: entry.is_local,
          reason_type: entry.reason_type,
          reason_tag: entry.reason_tag,
          active: true,
          computed_at: now,
          inserted_at: now,
          updated_at: now
        }
      end)

    retired_before = cutoff(settings.retired_ttl_hours, now)

    Repo.transaction(fn ->
      Repo.update_all(from(e in FeedEntry, where: e.active == true), set: [active: false])

      rows
      |> Enum.chunk_every(@insert_batch)
      |> Enum.each(fn batch ->
        Repo.insert_all(FeedEntry, batch,
          on_conflict: {:replace_all_except, [:post_id, :inserted_at]},
          conflict_target: :post_id
        )
      end)

      Repo.delete_all(
        from(e in FeedEntry, where: e.active == false and e.computed_at < ^retired_before)
      )
    end)
  end
end
