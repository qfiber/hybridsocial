defmodule HybridsocialWeb.Serializers.PostSerializer do
  @moduledoc """
  Shared post serialization for API responses.
  Enriches posts with user-specific state, reactions breakdown,
  link previews, mentions, tags, and custom emoji.
  """

  import Ecto.Query

  alias Hybridsocial.Repo
  alias Hybridsocial.Social.{Reaction, Boost, Bookmark, PostMute, Poll, PollOption, PollVote}
  alias Hybridsocial.Media.MediaFile
  alias Hybridsocial.Content.{LinkPreviews, CustomEmoji}

  @doc """
  Serializes a single post. Pass current_identity_id to include
  user-specific state (boosted, bookmarked, muted, current_reaction).
  """
  def serialize(post, opts \\ [])

  def serialize(%{deleted_at: deleted_at} = post, _opts) when not is_nil(deleted_at) do
    serialize_tombstone(post.id)
  end

  def serialize(post, opts) do
    current_identity_id = Keyword.get(opts, :current_identity_id)
    # Compute staff flag once per call. Cheap (single roles lookup);
    # callers in `serialize_many` precompute and pass via opts to
    # avoid N lookups across a batch.
    is_staff? =
      Keyword.get_lazy(opts, :is_staff, fn ->
        current_identity_id && Hybridsocial.Auth.RBAC.staff?(current_identity_id)
      end)

    badges =
      Hybridsocial.Badges.badges_for_post(
        post.identity,
        group_id: post.group_id,
        page_id: post.page_id
      )

    account = serialize_account(post.identity, badges)

    # Recurse into the quote chain up to `:quote_depth` levels (default
    # 2 — outer → quoted → quoted-of-quoted). Posts often quote a quote
    # that owns the actual media; without this we render an empty card.
    # Preload `quote: :identity` so the next recursion step finds the
    # nested quote's identity loaded and can serialize it.
    quote_depth = Keyword.get(opts, :quote_depth, 2)

    quote_post =
      case {post.quote, quote_depth} do
        {%Hybridsocial.Social.Post{} = q, depth} when depth > 0 ->
          q = Repo.preload(q, [:identity, quote: :identity])
          serialize(q, Keyword.put(opts, :quote_depth, depth - 1))

        _ ->
          nil
      end

    sensitive =
      case post.identity do
        %{force_sensitive: true} -> true
        _ -> post.sensitive
      end

    # User-specific state
    {is_boosted, is_bookmarked, is_muted, current_reaction} =
      if current_identity_id do
        user_state_for(post.id, current_identity_id)
      else
        {false, false, false, nil}
      end

    # Reactions breakdown
    reactions = reactions_for(post.id, current_identity_id)

    # Link preview
    card = card_for(post)

    # Mentions extracted from content
    mentions = extract_mentions(post.content_html || post.content || "")

    # Hashtags linked to this post
    tags = tags_for(post.id)

    # Custom emoji used in content
    emojis = emojis_for_post(post)

    # In reply to account
    in_reply_to_account_id = in_reply_to_account_id(post)

    # Media attachments
    media_attachments = media_attachments_for(post.id)

    # Per-image reply + reaction counts (Instagram-style heart per
    # image). Only run these aggregates when the post owns media —
    # avoids burning two queries for every text-only post in a feed.
    {media_reply_counts, media_reaction_counts} =
      media_counts_for(post.id, media_attachments)

    # When this post is a per-image reply, include the parent's image
    # number (1-based) + preview url so the card can render
    # "Replying to image N" with a thumbnail instead of just the
    # generic "Replying to a specific image". Skips the lookup
    # entirely for posts that aren't pinned to a media.
    target_media_summary =
      case Map.get(post, :target_media_id) do
        nil -> nil
        media_id -> target_media_summary_for(post.parent_id, media_id)
      end

    # URIs
    base_url = HybridsocialWeb.Endpoint.url()

    %{
      id: post.id,
      type: post.post_type,
      uri: post.ap_id || "#{base_url}/posts/#{post.id}",
      url: "#{base_url}/post/#{post.id}",
      content: post.content,
      content_html: post.content_html,
      visibility: post.visibility,
      sensitive: sensitive,
      spoiler_text: post.spoiler_text,
      language: post.language,
      reply_count: post.reply_count,
      boost_count: post.boost_count,
      reaction_count: post.reaction_count,
      is_pinned: post.is_pinned,
      # Which scope the pin actually applies to. Lets the client hide
      # the "Pinned" badge / Unpin action on feeds outside that scope,
      # so a group-pin doesn't read as a profile-pin when the same
      # post shows up on the author's parent profile timeline.
      pin_scope: pin_scope_name(post),
      is_boosted: is_boosted,
      is_bookmarked: is_bookmarked,
      is_muted: is_muted,
      current_user_reaction: current_reaction,
      created_at: post.inserted_at,
      # Feeds order by `last_activity_at` (a reply bumps every ancestor),
      # so without it the client can't explain why an old post resurfaced.
      last_activity_at: post.last_activity_at,
      edited_at: post.edited_at,
      edit_expires_at: Map.get(post, :edit_expires_at),
      account: account,
      parent_id: post.parent_id,
      root_id: post.root_id,
      target_media_id: Map.get(post, :target_media_id),
      target_media_index: target_media_summary && target_media_summary.index,
      target_media_preview_url: target_media_summary && target_media_summary.preview_url,
      media_reply_counts: media_reply_counts,
      media_reaction_counts: media_reaction_counts,
      in_reply_to_account_id: in_reply_to_account_id,
      quote: quote_post,
      card: card,
      mentions: mentions,
      tags: tags,
      emojis: emojis,
      reactions: reactions,
      media_attachments: media_attachments,
      poll: poll_for(post, current_identity_id),
      group: group_summary_for(post),
      page: page_summary_for(post, current_identity_id)
    }
    |> maybe_put_staff_fields(post, is_staff?)
  end

  # Staff-only fields: things that leak moderation signal to regular
  # users (pending-report counts, admin-hidden, reply-lock) are only
  # included when the viewer has staff. Defaults apply on the client
  # side for everyone else.
  defp maybe_put_staff_fields(payload, _post, false), do: payload
  defp maybe_put_staff_fields(payload, _post, nil), do: payload

  defp maybe_put_staff_fields(payload, post, _is_staff) do
    Map.merge(payload, %{
      open_report_count: post.open_report_count || 0,
      hidden_at: Map.get(post, :hidden_at),
      replies_locked_at: Map.get(post, :replies_locked_at)
    })
  end

  @doc """
  Serializes a list of posts, batch-loading user state for efficiency.
  """
  def serialize_many(posts, opts \\ []) do
    current_identity_id = Keyword.get(opts, :current_identity_id)

    is_staff? =
      current_identity_id && Hybridsocial.Auth.RBAC.staff?(current_identity_id)

    # Thread through to `serialize/2` for quote preloads so a quoted
    # post also picks up staff fields without doing a second RBAC
    # lookup per item.
    opts = Keyword.put(opts, :is_staff, is_staff?)
    post_ids = Enum.map(posts, & &1.id)

    # Batch load user state
    {boosts_set, bookmarks_set, mutes_set, reactions_map} =
      if current_identity_id do
        batch_user_state(post_ids, current_identity_id)
      else
        {MapSet.new(), MapSet.new(), MapSet.new(), %{}}
      end

    # Batch load reactions breakdown
    reactions_breakdown = batch_reactions(post_ids, current_identity_id)

    # Batch load media attachments (one query for the whole list)
    media_by_post = batch_media_attachments(post_ids)

    # Batch resolve target_media summaries (per-image replies). One
    # query for all unique parent_ids referenced by posts in the
    # batch, then index-lookup per post. Skipped entirely when no
    # post in the batch is a per-image reply.
    target_media_summaries = batch_target_media_summaries(posts)

    Enum.map(posts, fn post ->
      badges =
        Hybridsocial.Badges.badges_for_post(
          post.identity,
          group_id: post.group_id,
          page_id: post.page_id
        )

      account = serialize_account(post.identity, badges)

      quote_depth = Keyword.get(opts, :quote_depth, 2)

      quote_post =
        case {post.quote, quote_depth} do
          {%Hybridsocial.Social.Post{} = q, depth} when depth > 0 ->
            q = Repo.preload(q, [:identity, quote: :identity])
            serialize(q, Keyword.put(opts, :quote_depth, depth - 1))

          _ ->
            nil
        end

      sensitive =
        case post.identity do
          %{force_sensitive: true} -> true
          _ -> post.sensitive
        end

      card = card_for(post)
      mentions = extract_mentions(post.content_html || post.content || "")
      tags = tags_for(post.id)
      emojis = emojis_for_post(post)
      in_reply_to_account_id = in_reply_to_account_id(post)

      base_url = HybridsocialWeb.Endpoint.url()

      %{
        id: post.id,
        type: post.post_type,
        uri: post.ap_id || "#{base_url}/posts/#{post.id}",
        url: "#{base_url}/post/#{post.id}",
        content: post.content,
        content_html: post.content_html,
        visibility: post.visibility,
        sensitive: sensitive,
        spoiler_text: post.spoiler_text,
        language: post.language,
        reply_count: post.reply_count,
        boost_count: post.boost_count,
        reaction_count: post.reaction_count,
        is_pinned: post.is_pinned,
        pin_scope: pin_scope_name(post),
        is_boosted: MapSet.member?(boosts_set, post.id),
        is_bookmarked: MapSet.member?(bookmarks_set, post.id),
        is_muted: MapSet.member?(mutes_set, post.id),
        current_user_reaction: Map.get(reactions_map, post.id),
        created_at: post.inserted_at,
        last_activity_at: post.last_activity_at,
        edited_at: post.edited_at,
        edit_expires_at: Map.get(post, :edit_expires_at),
        account: account,
        parent_id: post.parent_id,
        root_id: post.root_id,
        target_media_id: Map.get(post, :target_media_id),
        target_media_index: get_in(target_media_summaries, [post.id, :index]),
        target_media_preview_url: get_in(target_media_summaries, [post.id, :preview_url]),
        in_reply_to_account_id: in_reply_to_account_id,
        quote: quote_post,
        card: card,
        mentions: mentions,
        tags: tags,
        emojis: emojis,
        reactions: Map.get(reactions_breakdown, post.id, []),
        media_attachments: Map.get(media_by_post, post.id, []),
        poll: poll_for(post, current_identity_id),
        group: group_summary_for(post),
        page: page_summary_for(post, current_identity_id)
      }
      |> maybe_put_staff_fields(post, is_staff?)
    end)
  end

  @doc """
  Layer a viewer's interaction state onto an already-serialized list of
  posts that was produced anonymously (`current_identity_id: nil`).

  This exists so a prewarmed, viewer-independent feed snapshot (see
  `Hybridsocial.Feeds.Snapshot`) can be reused for a logged-in viewer
  without re-running the expensive content serialization — only the cheap
  per-viewer lookups run here.

  The input is the cache-round-tripped snapshot, so every map is
  string-keyed; the patched fields are written with string keys to match.

  IMPORTANT: the set of fields patched here must stay in sync with the
  viewer-dependent fields in `serialize_many/2`: `is_boosted`,
  `is_bookmarked`, `is_muted`, `current_user_reaction`, the per-reaction
  `me` flag, poll `voted` / `own_votes`, and `page.can_edit`. Staff-only
  moderation fields are intentionally NOT added — the prewarmed first page
  omits them.
  """
  def apply_viewer_state(serialized, nil), do: serialized
  def apply_viewer_state([], _viewer_id), do: []

  def apply_viewer_state(serialized, viewer_id) do
    post_ids = Enum.map(serialized, & &1["id"])
    {boosts, bookmarks, mutes, reactions_map} = batch_user_state(post_ids, viewer_id)

    my_reactions =
      Reaction
      |> where([r], r.post_id in ^post_ids and r.identity_id == ^viewer_id)
      |> select([r], {r.post_id, r.type})
      |> Repo.all()
      |> MapSet.new()

    Enum.map(serialized, fn post ->
      id = post["id"]

      post
      |> Map.put("is_boosted", MapSet.member?(boosts, id))
      |> Map.put("is_bookmarked", MapSet.member?(bookmarks, id))
      |> Map.put("is_muted", MapSet.member?(mutes, id))
      |> Map.put("current_user_reaction", Map.get(reactions_map, id))
      |> patch_reactions_me(id, my_reactions)
      |> patch_poll_votes(id, viewer_id)
      |> patch_page_can_edit(viewer_id)
    end)
  end

  # `page.can_edit` is viewer-dependent — whether THIS viewer may edit/delete a
  # post authored as a page. The anonymous snapshot bakes it `false`; recompute
  # it for the real viewer so a page's managers still see Edit/Delete on their
  # own page's posts on a prewarmed public timeline. Only page-anchored posts
  # pay the per-post check; everything else short-circuits.
  defp patch_page_can_edit(%{"page" => %{"id" => page_id} = page} = post, viewer_id)
       when is_binary(page_id) do
    Map.put(
      post,
      "page",
      Map.put(page, "can_edit", Hybridsocial.Pages.can_edit?(page_id, viewer_id))
    )
  end

  defp patch_page_can_edit(post, _viewer_id), do: post

  # Recompute only the per-viewer `me` flag on each reaction; the counts
  # in the snapshot are viewer-independent and stay as-is.
  defp patch_reactions_me(post, id, my_reactions) do
    case post["reactions"] do
      reactions when is_list(reactions) ->
        patched =
          Enum.map(reactions, fn r ->
            Map.put(r, "me", MapSet.member?(my_reactions, {id, r["name"]}))
          end)

        Map.put(post, "reactions", patched)

      _ ->
        post
    end
  end

  # Poll `voted` / `own_votes` are per-viewer. Re-derive the whole poll
  # object for poll posts only (rare in these feeds); reuse poll_for/2,
  # which needs just post_type + id.
  defp patch_poll_votes(%{"type" => "poll"} = post, id, viewer_id) do
    Map.put(post, "poll", poll_for(%{post_type: "poll", id: id}, viewer_id))
  end

  defp patch_poll_votes(post, _id, _viewer_id), do: post

  @doc "Serialize a tombstone placeholder for unavailable posts."
  def serialize_tombstone(id) do
    %{
      id: id,
      type: "tombstone",
      content: nil,
      content_html: nil,
      tombstone: %{reason: "deleted"}
    }
  end

  # --- Account ---

  def serialize_account(nil, _badges), do: nil

  def serialize_account(%Hybridsocial.Accounts.Identity{} = identity, badges) do
    domain = extract_domain(identity)
    verification_tier = Map.get(identity, :verification_tier)

    %{
      id: identity.id,
      type: HybridsocialWeb.Helpers.Account.api_type(identity.type),
      handle: identity.handle,
      acct: HybridsocialWeb.Helpers.Account.build_acct(identity),
      display_name: identity.display_name,
      # Custom emojis so `:shortcode:` in a post author's display_name renders.
      emojis: Map.get(identity, :emojis, []) || [],
      avatar_url: identity.avatar_url,
      header_url: Map.get(identity, :header_url, nil),
      bio: Map.get(identity, :bio, nil),
      bio_html:
        if is_struct(identity, Hybridsocial.Accounts.Identity) do
          Hybridsocial.Accounts.bio_html(identity)
        else
          nil
        end,
      is_bot: Map.get(identity, :is_bot, false),
      is_locked: Map.get(identity, :is_locked, false),
      badges: badges,
      verification_tier: verification_tier,
      is_verified: verified_tier?(verification_tier),
      domain: domain,
      # Was Map.get(identity, :url) — but Identity has no :url field, so this
      # was always nil. Use the profile_url helper (profile_url || ap_actor_url).
      url: HybridsocialWeb.Helpers.Account.profile_url(identity),
      created_at: identity.inserted_at
    }
  end

  def serialize_account(_, _), do: nil

  defp verified_tier?(tier) when tier in ["verified_starter", "verified_creator", "verified_pro"],
    do: true

  defp verified_tier?(_), do: false

  # --- Private helpers ---

  defp user_state_for(post_id, identity_id) do
    is_boosted =
      Boost
      |> where(
        [b],
        b.post_id == ^post_id and b.identity_id == ^identity_id and is_nil(b.deleted_at)
      )
      |> Repo.exists?()

    is_bookmarked =
      Bookmark
      |> where([b], b.post_id == ^post_id and b.identity_id == ^identity_id)
      |> Repo.exists?()

    is_muted =
      PostMute
      |> where([m], m.post_id == ^post_id and m.identity_id == ^identity_id)
      |> Repo.exists?()

    current_reaction =
      Reaction
      |> where([r], r.post_id == ^post_id and r.identity_id == ^identity_id)
      |> select([r], r.type)
      |> Repo.one()

    {is_boosted, is_bookmarked, is_muted, current_reaction}
  end

  defp batch_user_state(post_ids, identity_id) when post_ids != [] do
    boosts =
      Boost
      |> where(
        [b],
        b.post_id in ^post_ids and b.identity_id == ^identity_id and is_nil(b.deleted_at)
      )
      |> select([b], b.post_id)
      |> Repo.all()
      |> MapSet.new()

    bookmarks =
      Bookmark
      |> where([b], b.post_id in ^post_ids and b.identity_id == ^identity_id)
      |> select([b], b.post_id)
      |> Repo.all()
      |> MapSet.new()

    mutes =
      PostMute
      |> where([m], m.post_id in ^post_ids and m.identity_id == ^identity_id)
      |> select([m], m.post_id)
      |> Repo.all()
      |> MapSet.new()

    reactions =
      Reaction
      |> where([r], r.post_id in ^post_ids and r.identity_id == ^identity_id)
      |> select([r], {r.post_id, r.type})
      |> Repo.all()
      |> Map.new()

    {boosts, bookmarks, mutes, reactions}
  end

  defp batch_user_state(_, _), do: {MapSet.new(), MapSet.new(), MapSet.new(), %{}}

  defp reactions_for(post_id, current_identity_id) do
    rows =
      Reaction
      |> where([r], r.post_id == ^post_id)
      |> group_by([r], r.type)
      |> select([r], {r.type, count(r.id)})
      |> Repo.all()

    Enum.map(rows, fn {type, count} ->
      me =
        if current_identity_id do
          Reaction
          |> where(
            [r],
            r.post_id == ^post_id and r.type == ^type and r.identity_id == ^current_identity_id
          )
          |> Repo.exists?()
        else
          false
        end

      %{name: type, count: count, me: me}
    end)
  end

  defp batch_reactions(post_ids, current_identity_id) when post_ids != [] do
    # Group reactions by post_id and type
    rows =
      Reaction
      |> where([r], r.post_id in ^post_ids)
      |> group_by([r], [r.post_id, r.type])
      |> select([r], {r.post_id, r.type, count(r.id)})
      |> Repo.all()

    # Get current user's reactions
    my_reactions =
      if current_identity_id do
        Reaction
        |> where([r], r.post_id in ^post_ids and r.identity_id == ^current_identity_id)
        |> select([r], {r.post_id, r.type})
        |> Repo.all()
        |> MapSet.new()
      else
        MapSet.new()
      end

    rows
    |> Enum.group_by(fn {post_id, _type, _count} -> post_id end)
    |> Map.new(fn {post_id, entries} ->
      reactions =
        Enum.map(entries, fn {_pid, type, count} ->
          %{name: type, count: count, me: MapSet.member?(my_reactions, {post_id, type})}
        end)

      {post_id, reactions}
    end)
  end

  defp batch_reactions(_, _), do: %{}

  # Polls. Skip the lookup for non-poll posts so the home feed
  # doesn't pay an N+1 hit per row. For poll posts (local OR remote
  # — both flavours land in the same table now that
  # Federation.Inbox.persist_remote_poll runs on ingest) we shape
  # the row into the Mastodon-style `poll` object the frontend's
  # `Poll` type expects: `multiple` (not multiple_choice),
  # `expired` boolean, `options[].title` (not `text`), per-viewer
  # `voted` and `own_votes` indices.
  defp poll_for(%{post_type: "poll", id: post_id}, viewer_id) do
    case Repo.one(from p in Poll, where: p.post_id == ^post_id) do
      nil ->
        nil

      poll ->
        options =
          PollOption
          |> where([o], o.poll_id == ^poll.id)
          |> order_by([o], asc: o.position)
          |> Repo.all()

        own_votes =
          if viewer_id do
            from(v in PollVote,
              where: v.poll_id == ^poll.id and v.identity_id == ^viewer_id,
              select: v.option_id
            )
            |> Repo.all()
          else
            []
          end

        own_indices =
          options
          |> Enum.with_index()
          |> Enum.flat_map(fn {opt, idx} ->
            if opt.id in own_votes, do: [idx], else: []
          end)

        votes_count = Enum.reduce(options, 0, fn o, acc -> acc + (o.votes_count || 0) end)

        %{
          id: poll.id,
          expires_at: poll.expires_at,
          expired: poll_expired?(poll.expires_at),
          multiple: poll.multiple_choice,
          votes_count: votes_count,
          voters_count: poll.voters_count,
          voted: own_indices != [],
          own_votes: own_indices,
          options:
            Enum.map(options, fn o ->
              %{title: o.text, votes_count: o.votes_count}
            end)
        }
    end
  end

  defp poll_for(_post, _viewer_id), do: nil

  defp poll_expired?(nil), do: false

  defp poll_expired?(%DateTime{} = expires_at) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  defp poll_expired?(%NaiveDateTime{} = expires_at) do
    case DateTime.from_naive(expires_at, "Etc/UTC") do
      {:ok, dt} -> DateTime.compare(DateTime.utc_now(), dt) == :gt
      _ -> false
    end
  end

  defp poll_expired?(_), do: false

  defp card_for(post) do
    # Wrap in rescue: a misbehaving link preview (varchar overflow,
    # network error mid-fetch, malformed HTML) is not worth 500ing
    # the whole timeline over. Treat any failure as "no card" and
    # let the post serialize without one.
    try do
      case LinkPreviews.preview_for_post(post) do
        {:ok, preview} ->
          %{
            url: preview.url,
            title: preview.title,
            description: preview.description,
            image: preview.image_url,
            provider_name: preview.site_name
          }

        _ ->
          nil
      end
    rescue
      e ->
        require Logger
        Logger.warning("card_for failed for post #{post.id}: #{Exception.message(e)}")
        nil
    end
  end

  # --- Media attachments ---

  # Per-image reply + reaction counts. No media → no queries, empty maps.
  defp media_counts_for(_post_id, []), do: {%{}, %{}}

  defp media_counts_for(post_id, _media_attachments) do
    {media_reply_counts_for(post_id), media_reaction_counts_for(post_id)}
  end

  defp media_attachments_for(post_id) do
    MediaFile
    |> where([m], m.post_id == ^post_id and is_nil(m.deleted_at))
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
    |> Enum.map(&serialize_media_attachment/1)
  end

  defp batch_media_attachments([]), do: %{}

  defp batch_media_attachments(post_ids) do
    MediaFile
    |> where([m], m.post_id in ^post_ids and is_nil(m.deleted_at))
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
    |> Enum.group_by(& &1.post_id, &serialize_media_attachment/1)
  end

  # --- Per-image reply counts ---

  # Returns a %{media_id => count} map for replies that pinned
  # themselves to a specific media on this post. Excludes replies
  # whose target_media has since been deleted (the FK is nilify_all
  # on media delete, so those rows fall out naturally).
  defp media_reply_counts_for(post_id) do
    Hybridsocial.Social.Post
    |> where([p], p.parent_id == ^post_id)
    |> where([p], not is_nil(p.target_media_id))
    |> where([p], is_nil(p.deleted_at))
    |> group_by([p], p.target_media_id)
    |> select([p], {p.target_media_id, count(p.id)})
    |> Repo.all()
    |> Map.new()
  end

  # Resolves a target_media_id to its 1-based position in the parent
  # post's gallery + a preview url. Returns nil when the parent has
  # been deleted or the media has been removed (FK is nilify_all so
  # `target_media_id` may legitimately point to a row that no longer
  # exists in `media`). Same ordering as `media_attachments_for/1`.
  defp target_media_summary_for(nil, _media_id), do: nil

  defp target_media_summary_for(parent_id, media_id) do
    medias =
      MediaFile
      |> where([m], m.post_id == ^parent_id and is_nil(m.deleted_at))
      |> order_by([m], asc: m.inserted_at)
      |> Repo.all()

    case Enum.find_index(medias, &(&1.id == media_id)) do
      nil ->
        nil

      idx ->
        media = Enum.at(medias, idx)

        url =
          if is_binary(media.remote_url) do
            Hybridsocial.Media.MediaProxy.url(media.remote_url)
          else
            Hybridsocial.Media.media_url(media)
          end

        preview_url = thumbnail_url(media) || url

        %{index: idx + 1, preview_url: preview_url}
    end
  end

  # Build a `%{post_id => %{index, preview_url}}` map for every post
  # in the batch that's pinned to a specific media on its parent.
  # One query loads media for all referenced parents; per-post we
  # find the media's position + preview URL in the gallery.
  defp batch_target_media_summaries(posts) do
    pairs =
      posts
      |> Enum.flat_map(fn p ->
        case {Map.get(p, :target_media_id), Map.get(p, :parent_id)} do
          {media_id, parent_id} when is_binary(media_id) and is_binary(parent_id) ->
            [{p.id, parent_id, media_id}]

          _ ->
            []
        end
      end)

    if pairs == [] do
      %{}
    else
      parent_ids = pairs |> Enum.map(fn {_pid, parent_id, _mid} -> parent_id end) |> Enum.uniq()

      medias_by_parent =
        MediaFile
        |> where([m], m.post_id in ^parent_ids and is_nil(m.deleted_at))
        |> order_by([m], asc: m.inserted_at)
        |> Repo.all()
        |> Enum.group_by(& &1.post_id)

      Enum.reduce(pairs, %{}, fn {pid, parent_id, media_id}, acc ->
        medias = Map.get(medias_by_parent, parent_id, [])

        case Enum.find_index(medias, &(&1.id == media_id)) do
          nil ->
            acc

          idx ->
            media = Enum.at(medias, idx)

            url =
              if is_binary(media.remote_url) do
                Hybridsocial.Media.MediaProxy.url(media.remote_url)
              else
                Hybridsocial.Media.media_url(media)
              end

            preview_url = thumbnail_url(media) || url

            Map.put(acc, pid, %{index: idx + 1, preview_url: preview_url})
        end
      end)
    end
  end

  # Returns a `%{media_id => count}` map of reactions scoped to a
  # specific image on this post. Mirrors `media_reply_counts_for/1`.
  defp media_reaction_counts_for(post_id) do
    Hybridsocial.Social.Reaction
    |> where([r], r.post_id == ^post_id)
    |> where([r], not is_nil(r.target_media_id))
    |> group_by([r], r.target_media_id)
    |> select([r], {r.target_media_id, count(r.id)})
    |> Repo.all()
    |> Map.new()
  end

  def serialize_media_attachment(%MediaFile{} = media) do
    # Remote attachments live on the author's instance. We rewrite
    # the URL through our media proxy so the client never reveals
    # its IP / UA to the remote host. Local uploads keep their
    # direct media_url.
    {url, remote_url} =
      if is_binary(media.remote_url) do
        {Hybridsocial.Media.MediaProxy.url(media.remote_url), media.remote_url}
      else
        {Hybridsocial.Media.media_url(media), nil}
      end

    %{
      id: media.id,
      type: media_type_for(media.content_type),
      url: url,
      preview_url: thumbnail_url(media) || url,
      remote_url: remote_url,
      description: media.alt_text,
      blurhash: media.blurhash,
      meta: %{
        original: %{
          width: media.width,
          height: media.height,
          duration: media.duration,
          size: media.file_size,
          content_type: media.content_type
        }
      }
    }
  end

  defp media_type_for(content_type) when is_binary(content_type) do
    cond do
      String.starts_with?(content_type, "image/") -> "image"
      String.starts_with?(content_type, "video/") -> "video"
      String.starts_with?(content_type, "audio/") -> "audio"
      true -> "unknown"
    end
  end

  defp media_type_for(_), do: "unknown"

  defp thumbnail_url(%MediaFile{thumbnail_path: path}) when is_binary(path) and path != "" do
    Hybridsocial.Media.Storage.url(path)
  end

  defp thumbnail_url(_), do: nil

  defp extract_mentions(html) when is_binary(html) do
    # Extract @mentions from content — look for links with class="mention" or @handle patterns
    mention_regex = ~r/@([a-zA-Z0-9_]+(?:@[a-zA-Z0-9.\-]+)?)/

    Regex.scan(mention_regex, html)
    |> Enum.map(fn [_, acct] -> %{acct: acct} end)
    |> Enum.uniq_by(& &1.acct)
  end

  defp extract_mentions(_), do: []

  # Compact group/page summary so a post rendered in a feed can show
  # a "from <Group>" / "from <Page>" chip without the client needing
  # an extra round trip. Wrapped in try/rescue so a schema mismatch
  # (or a deleted row) can never 500 the whole timeline — the chip
  # just renders nil and the post still ships.
  defp group_summary_for(%{group_id: nil}), do: nil

  defp group_summary_for(%{group_id: id}) when is_binary(id) do
    try do
      case Repo.get(Hybridsocial.Groups.Group, id) do
        nil -> nil
        g -> %{id: g.id, name: g.name, avatar_url: g.avatar_url, visibility: g.visibility}
      end
    rescue
      _ -> nil
    end
  end

  defp group_summary_for(_), do: nil

  # Pages are stored as Identity rows with type="organization" — there
  # is no Hybridsocial.Pages.Page schema. Use Pages.get_page/1 which
  # preloads the organization, and synthesize a {id, name, avatar} chip
  # off the identity / organization fields.
  defp page_summary_for(%{page_id: nil}, _viewer_id), do: nil

  defp page_summary_for(%{page_id: id}, viewer_id) when is_binary(id) do
    try do
      case Hybridsocial.Pages.get_page(id) do
        nil ->
          nil

        identity ->
          name =
            case Map.get(identity, :organization) do
              %{name: n} when is_binary(n) and n != "" -> n
              _ -> identity.display_name || identity.handle
            end

          # `can_edit` tells the client whether THIS viewer may edit/delete the
          # post (it's authored as the page, so the strict author == viewer
          # check the UI uses otherwise fails). Mirrors get_owned_post's
          # page path: anyone Pages.can_edit? can edit and delete its posts.
          can_edit = is_binary(viewer_id) and Hybridsocial.Pages.can_edit?(id, viewer_id)

          %{id: identity.id, name: name, avatar_url: identity.avatar_url, can_edit: can_edit}
      end
    rescue
      _ -> nil
    end
  end

  defp page_summary_for(_, _viewer_id), do: nil

  defp tags_for(post_id) do
    {:ok, post_uuid} = Ecto.UUID.dump(post_id)

    query =
      from ph in "post_hashtags",
        join: h in Hybridsocial.Social.Hashtag,
        on: h.id == ph.hashtag_id,
        where: ph.post_id == ^post_uuid,
        select: %{name: h.name, display_name: h.display_name}

    base_url = HybridsocialWeb.Endpoint.url()

    Repo.all(query)
    |> Enum.map(fn tag ->
      # Display the first-seen casing if recorded, else fall back to
      # the lowercase canonical. URL stays canonical for routing.
      %{
        name: tag.display_name || tag.name,
        slug: tag.name,
        url: "#{base_url}/tags/#{tag.name}"
      }
    end)
  end

  defp emojis_in_content(content) do
    # Find :shortcode: patterns in content
    shortcodes =
      ~r/:([a-zA-Z0-9_]+):/
      |> Regex.scan(content)
      |> Enum.map(fn [_, code] -> code end)
      |> Enum.uniq()

    if shortcodes != [] do
      CustomEmoji
      |> where([e], e.shortcode in ^shortcodes and e.enabled == true)
      |> Repo.all()
      |> Enum.map(fn emoji ->
        %{
          shortcode: emoji.shortcode,
          url: emoji.image_url,
          static_url: emoji.image_url,
          category: emoji.category
        }
      end)
    else
      []
    end
  end

  defp in_reply_to_account_id(%{parent: %Hybridsocial.Social.Post{identity_id: id}}), do: id
  defp in_reply_to_account_id(%{parent_id: nil}), do: nil

  defp in_reply_to_account_id(%{parent_id: parent_id}) when is_binary(parent_id) do
    Hybridsocial.Social.Post
    |> where([p], p.id == ^parent_id)
    |> select([p], p.identity_id)
    |> Repo.one()
  end

  defp in_reply_to_account_id(_), do: nil

  defp extract_domain(identity) do
    url = Map.get(identity, :url, nil)

    if url do
      case URI.parse(url) do
        %URI{host: host} when is_binary(host) ->
          local_host = URI.parse(HybridsocialWeb.Endpoint.url()).host
          if host == local_host, do: nil, else: host

        _ ->
          nil
      end
    else
      nil
    end
  end

  # Mirrors `Posts.pin_scope/1` but returns the string the API client
  # wants so the frontend doesn't have to know the precedence rules
  # (group > page > profile).
  defp pin_scope_name(%{group_id: gid}) when is_binary(gid), do: "group"
  defp pin_scope_name(%{page_id: pid}) when is_binary(pid), do: "page"
  defp pin_scope_name(_), do: "profile"

  # Merge two emoji sources into one deduplicated list:
  #   1. `post.emojis` — the per-post manifest the federation inbox
  #      built from the AP `tag` Emoji entries. Authoritative for
  #      remote posts, since the remote instance is the one that
  #      knows what `:blobcatgooglywanted2:` looks like over there.
  #   2. The instance-wide `custom_emojis` table — matches by
  #      shortcode against the post text. Covers local posts that
  #      reference admin-curated emojis without a per-post manifest.
  #
  # The per-post manifest wins on shortcode conflicts so a federated
  # `:fire:` keeps its source-instance glyph instead of being replaced
  # by ours.
  defp emojis_for_post(post) do
    federated = serialize_post_emojis(Map.get(post, :emojis))
    local = emojis_in_content(post.content || "")

    seen = MapSet.new(Enum.map(federated, & &1.shortcode))

    local_unique =
      Enum.reject(local, fn e -> MapSet.member?(seen, e.shortcode) end)

    federated ++ local_unique
  end

  # Normalize whatever Ecto handed back for the row's `:emojis` array
  # column to a stable `[%{shortcode, url, static_url}]` shape.
  defp serialize_post_emojis(emojis) when is_list(emojis) do
    emojis
    |> Enum.map(fn entry ->
      shortcode = Map.get(entry, "shortcode") || Map.get(entry, :shortcode)
      url = Map.get(entry, "url") || Map.get(entry, :url)
      static_url = Map.get(entry, "static_url") || Map.get(entry, :static_url) || url

      if is_binary(shortcode) and is_binary(url) do
        %{shortcode: shortcode, url: url, static_url: static_url}
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp serialize_post_emojis(_), do: []
end
