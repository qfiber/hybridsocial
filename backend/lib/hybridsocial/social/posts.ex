defmodule Hybridsocial.Social.Posts do
  @moduledoc """
  Context module for managing posts, reactions, boosts, and hashtags.
  """
  import Ecto.Query
  alias Hybridsocial.Repo
  alias Hybridsocial.Social.{Post, PostRevision, Reaction, Boost, Hashtag, Polls}
  alias Hybridsocial.Premium.TierLimits
  alias Hybridsocial.Content.Emojis
  alias Hybridsocial.Config

  @default_page_size 20

  # --- Post CRUD ---

  def create_post(identity_id, attrs, identity \\ nil) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    limits = resolve_limits(identity)
    edit_expires_at = compute_edit_expires_at(now, limits[:edit_window] || 900)
    markdown_level = resolve_markdown_level(attrs, limits)
    content_html = maybe_render_content_html(attrs["content"], markdown_level)

    # Allocate the post ID up-front so we can stamp its canonical AP
    # URL into `ap_id` in the same insert. With this, `get_post_by_ap_id/1`
    # becomes an indexed lookup for both local and remote rows, and
    # every Delete/Update activity we emit references a value the
    # inbox can hand straight back to the DB.
    post_id = Map.get(attrs, "id") || Ecto.UUID.generate()
    ap_id = "#{HybridsocialWeb.Endpoint.url()}/posts/#{post_id}"

    scheduled_at = Map.get(attrs, "scheduled_at") || Map.get(attrs, :scheduled_at)

    # Scheduled posts stay unpublished until the worker picks them up;
    # everything else publishes immediately. We write `published_at`
    # here (not in the changeset helper) because the two-state rule
    # matters for federation timing — federate iff published_at is set.
    published_at =
      if future_datetime?(scheduled_at), do: nil, else: now

    post_attrs =
      attrs
      |> Map.put("id", post_id)
      |> Map.put("ap_id", ap_id)
      |> Map.put("identity_id", identity_id)
      |> Map.put("published_at", published_at)
      |> Map.put("content_html", content_html)
      |> maybe_resolve_root_id()
      |> maybe_resolve_parent_ap_id()

    changeset =
      %Post{}
      |> Post.create_changeset(post_attrs, char_limit: limits[:char_limit] || 5000)
      |> Ecto.Changeset.put_change(:published_at, published_at)
      # Scheduled posts (published_at = nil) get their last_activity_at
      # stamped by the scheduled-post worker at actual publish time;
      # immediate posts get it now.
      |> Ecto.Changeset.put_change(:last_activity_at, published_at)
      |> maybe_put_edit_expires_at(edit_expires_at)

    with {:ok, expires_at} <- resolve_expires_at(attrs, published_at || scheduled_at),
         :ok <- validate_premium_emojis(attrs["content"], identity),
         :ok <- check_trust_gates(identity, attrs),
         :ok <- Hybridsocial.Groups.authorize_group_post(post_attrs, identity_id),
         :ok <- check_thread_not_locked(post_attrs),
         :ok <- check_audio_allowed(attrs, limits),
         :ok <- check_target_media(post_attrs) do
      # Media is always uploaded under the human's identity, even when the post
      # is authored *as a page* (post.identity_id = page_id). Attach against the
      # uploader, not the post author, or a page post silently drops its media.
      changeset
      |> Ecto.Changeset.put_change(:expires_at, expires_at)
      |> insert_post(attrs, uploader_id(identity, identity_id))
    end
  end

  @doc """
  The instance-wide range a timed post's lifetime must fall in, in seconds.
  Admin-tunable via `post_expiry_min_seconds` / `post_expiry_max_seconds`.
  Whether an author may set a timer at all is the `post_expiry` tier limit.
  """
  def post_expiry_bounds do
    %{
      min: config_int("post_expiry_min_seconds", 300),
      max: config_int("post_expiry_max_seconds", 365 * 86_400)
    }
  end

  defp config_int(key, default) do
    case Config.get(key, default) do
      n when is_integer(n) -> n
      n when is_binary(n) -> parse_int(n) || default
      _ -> default
    end
  end

  # `expires_in` (seconds, the Pleroma/Akkoma status param) makes a timed
  # post: it is deleted that long after it publishes. A scheduled post's
  # clock starts at its scheduled time, not now.
  defp resolve_expires_at(attrs, base) do
    case Map.get(attrs, "expires_in") || Map.get(attrs, :expires_in) do
      blank when blank in [nil, ""] ->
        {:ok, nil}

      value ->
        %{min: min, max: max} = post_expiry_bounds()

        with seconds when is_integer(seconds) and seconds >= min and seconds <= max <-
               parse_int(value),
             %DateTime{} = base <- expiry_base(base) do
          # Adding in microseconds also lifts a whole-second scheduled_at to
          # the column's usec precision.
          {:ok, DateTime.add(base, seconds * 1_000_000, :microsecond)}
        else
          _ -> {:error, :invalid_expires_in, %{min: min, max: max}}
        end
    end
  end

  defp expiry_base(%DateTime{} = dt), do: DateTime.truncate(dt, :microsecond)

  defp expiry_base(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> DateTime.truncate(dt, :microsecond)
      _ -> nil
    end
  end

  defp expiry_base(_), do: nil

  defp parse_int(n) when is_integer(n), do: n

  defp parse_int(n) when is_binary(n) do
    case Integer.parse(String.trim(n)) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_int(_), do: nil

  @doc """
  Deletes up to `limit` local posts whose timer ran out by `now`, oldest
  first. Each goes through `delete_post/2`, so it federates a Delete and
  fixes reply counts like a manual delete. Returns the number deleted.
  """
  def delete_expired_posts(now \\ DateTime.utc_now(), limit \\ 500) do
    Post
    |> where([p], not is_nil(p.expires_at) and p.expires_at <= ^now and is_nil(p.deleted_at))
    |> order_by([p], asc: p.expires_at)
    |> limit(^limit)
    |> select([p], {p.id, p.identity_id})
    |> Repo.all()
    |> Enum.count(fn {id, identity_id} -> match?({:ok, _}, delete_post(id, identity_id)) end)
  end

  # If the reply pins itself to a specific media attachment, the
  # attachment must belong to the parent post — otherwise a reply on
  # post X could mis-target an image from post Y, which would show
  # up nowhere sensible. Replies without a parent_id are rejected
  # since per-image targeting only makes sense in a thread.
  defp check_target_media(%{"target_media_id" => nil}), do: :ok
  defp check_target_media(%{"target_media_id" => ""}), do: :ok

  defp check_target_media(%{"target_media_id" => media_id, "parent_id" => parent_id})
       when is_binary(media_id) and is_binary(parent_id) do
    media =
      Hybridsocial.Media.MediaFile
      |> where([m], m.id == ^media_id and is_nil(m.deleted_at))
      |> Repo.one()

    cond do
      is_nil(media) -> {:error, :target_media_not_found}
      media.post_id != parent_id -> {:error, :target_media_mismatch}
      true -> :ok
    end
  end

  defp check_target_media(%{"target_media_id" => media_id}) when is_binary(media_id) do
    {:error, :target_media_requires_parent}
  end

  defp check_target_media(_), do: :ok

  # Tier gate: if the user tries to post audio (either post_type=audio
  # or any attached media with an audio/* content type), their tier
  # must have `audio_allowed: true`. Free tier is blocked by default.
  #
  # The media upload endpoint already enforces `audio_allowed` before
  # a MediaFile is created, so in practice the post-creation check is
  # only defence-in-depth — a user can't skip the upload step. We
  # still verify here so tier downgrades between upload and post
  # don't silently succeed.
  defp check_audio_allowed(attrs, limits) do
    if audio_intent?(attrs) and limits[:audio_allowed] != true do
      {:error, :audio_not_allowed}
    else
      :ok
    end
  end

  defp audio_intent?(attrs) do
    post_type = Map.get(attrs, "post_type") || Map.get(attrs, :post_type)

    if post_type == "audio" do
      true
    else
      attrs
      |> media_ids_from_attrs()
      |> any_audio_media?()
    end
  end

  defp media_ids_from_attrs(attrs) do
    Map.get(attrs, "media_ids") || Map.get(attrs, :media_ids) || []
  end

  defp post_has_media?(post_id) do
    Hybridsocial.Media.MediaFile
    |> where([m], m.post_id == ^post_id and is_nil(m.deleted_at))
    |> Repo.exists?()
  end

  defp any_audio_media?([]), do: false

  defp any_audio_media?(ids) when is_list(ids) do
    Hybridsocial.Media.MediaFile
    |> where([m], m.id in ^ids and like(m.content_type, "audio/%"))
    |> Repo.exists?()
  end

  # If the target of a reply (parent or root) has been admin-locked,
  # reject the insert. We read both because a locked thread should
  # block new replies anywhere in the subtree, not just direct
  # replies to the locked node.
  defp check_thread_not_locked(%{"parent_id" => parent_id} = attrs)
       when is_binary(parent_id) do
    root_id = attrs["root_id"]

    ids = Enum.uniq([parent_id, root_id]) |> Enum.reject(&is_nil/1)

    locked_exists? =
      Post
      |> where([p], p.id in ^ids and not is_nil(p.replies_locked_at))
      |> Repo.exists?()

    if locked_exists?, do: {:error, :replies_locked}, else: :ok
  end

  defp check_thread_not_locked(_attrs), do: :ok

  defp resolve_limits(nil), do: TierLimits.limits_for_tier("verified_pro")
  defp resolve_limits(identity), do: TierLimits.limits_for(identity)

  # 0 means unlimited editing — TierLimits convention, mirrored by
  # the UI; don't stamp an edit_expires_at in that case.
  defp compute_edit_expires_at(_now, 0), do: nil

  defp compute_edit_expires_at(now, window) do
    now |> DateTime.add(window, :second) |> DateTime.truncate(:microsecond)
  end

  # Markdown level is capped by the author's tier (free → plaintext,
  # verified_pro → full GFM). The composer can opt *down* from that
  # ceiling by passing `markdown: false` (e.g. a pro user posting
  # plain-text). We never let the client opt *up* past their tier.
  defp resolve_markdown_level(attrs, limits) do
    tier_level = limits[:markdown] || "basic"

    case Map.get(attrs, "markdown") do
      false -> "none"
      "false" -> "none"
      0 -> "none"
      _ -> tier_level
    end
  end

  defp maybe_render_content_html(nil, _level), do: nil

  defp maybe_render_content_html(content, level),
    do: Hybridsocial.Content.Sanitizer.sanitize_post_content(content, level)

  defp maybe_put_edit_expires_at(changeset, nil), do: changeset

  defp maybe_put_edit_expires_at(changeset, expires_at),
    do: Ecto.Changeset.put_change(changeset, :edit_expires_at, expires_at)

  defp validate_premium_emojis(nil, _identity), do: :ok
  defp validate_premium_emojis(_content, nil), do: :ok

  defp validate_premium_emojis(content, identity) do
    case Emojis.validate_premium_emoji_access(content, identity) do
      :ok -> :ok
      {:error, shortcodes} -> {:error, :premium_emojis_required, shortcodes}
    end
  end

  # The human who uploaded the media and is authoring/editing the post. When a
  # post is authored *as a page* the scope id is the page, but media always
  # lives under the acting human's identity — see `attach_media/3`.
  defp uploader_id(nil, identity_id), do: identity_id
  defp uploader_id(identity, _identity_id), do: identity.id

  defp insert_post(changeset, attrs, uploader_id) do
    case Repo.insert(changeset) do
      {:ok, post} ->
        if post.content, do: extract_and_link_hashtags(post)

        if post.post_type == "poll" do
          poll_attrs = Map.take(attrs, ["options", "multiple_choice", "expires_at"])
          Polls.create_poll(post.id, poll_attrs)
        end

        attach_media(
          post,
          Map.get(attrs, "media_ids") || Map.get(attrs, :media_ids) || [],
          uploader_id
        )

        # Record mentions so direct-visibility posts surface in the
        # Direct tab for recipients (not just the author) and so
        # mention-based access checks can tell "addressed to you" from
        # "a followers-only post you happened to see the link for".
        mention_ids = persist_local_mentions(post, attrs)
        notify_mentions(post, mention_ids)

        # Increment parent's reply count + notify parent's author if
        # the reply is visible to them. Self-replies are skipped
        # inside notify_reply via the self-notification guard.
        if post.parent_id do
          increment_reply_count(post.parent_id)
          bump_thread_activity(post)
          notify_reply_to_parent(post)
        end

        # Quote posts notify the quoted author.
        if post.quote_id do
          notify_quote(post)
        end

        post = Repo.preload(post, [:media_attachments, :identity, poll: :options])

        # Scheduled posts defer every side effect that depends on
        # them being "live": no federation, no direct-post fan-out,
        # no PubSub notifications. The scheduler calls
        # `run_post_published_hooks/1` later, at publish time.
        if scheduled_for_future?(post) do
          {:ok, post}
        else
          {:ok, run_post_published_hooks(post)}
        end

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  # Thread-bumping: a new reply bumps `last_activity_at` on every
  # ancestor we can identify (parent + root). Timelines order by
  # `last_activity_at DESC` so the thread surfaces back up without
  # the reply itself needing to appear as a standalone item.
  #
  # We only bump if the reply is actually published — a scheduled
  # reply stamped for the future shouldn't pre-bump its thread. And
  # we use the reply's `published_at` as the new value (not NOW()),
  # so back-dated federation imports don't jerk things forward.
  @doc """
  Publicly callable alias for `bump_thread_activity/1` so the
  federation inbound path can bump local ancestors when a remote
  reply lands. Kept as a separate public name so the private helper
  stays scoped to the create-path call site.
  """
  def bump_thread_activity_public(%Post{} = post), do: bump_thread_activity(post)

  defp bump_thread_activity(%Post{published_at: nil}), do: :ok

  defp bump_thread_activity(%Post{published_at: bump_ts} = post) do
    ids = Enum.uniq([post.parent_id, post.root_id]) |> Enum.reject(&is_nil/1)

    if ids != [] do
      # Only bump forward — if a post already has a newer
      # `last_activity_at` (from another in-flight reply, say), leave
      # it. `GREATEST(COALESCE(...), ?)` handles both the never-set
      # and already-set-but-older cases.
      from(p in Post,
        where: p.id in ^ids,
        update: [
          set: [
            last_activity_at:
              fragment(
                "GREATEST(COALESCE(?, 'epoch'::timestamptz), ?)",
                p.last_activity_at,
                ^bump_ts
              )
          ]
        ]
      )
      |> Repo.update_all([])
    end

    :ok
  end

  defp scheduled_for_future?(%Post{scheduled_at: nil}), do: false

  defp scheduled_for_future?(%Post{scheduled_at: scheduled_at, published_at: published_at}) do
    # If `published_at` is already set, we've republished — not
    # scheduled. If `scheduled_at` is in the past, same deal.
    is_nil(published_at) and DateTime.compare(scheduled_at, DateTime.utc_now()) == :gt
  end

  defp future_datetime?(nil), do: false

  defp future_datetime?(%DateTime{} = dt),
    do: DateTime.compare(dt, DateTime.utc_now()) == :gt

  defp future_datetime?(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> DateTime.compare(dt, DateTime.utc_now()) == :gt
      _ -> false
    end
  end

  defp future_datetime?(_), do: false

  @doc """
  Fires the side effects that always follow a post becoming
  "published" — search indexing, direct-post realtime fan-out, and
  federation. Extracted so the scheduled-post worker can run them
  at publish time, since a scheduled post skips the normal create
  path and would otherwise federate nothing.

  Returns the post unchanged so it can be piped.
  """
  def run_post_published_hooks(%Post{} = post) do
    post = Repo.preload(post, [:media_attachments, :identity, poll: :options])

    # Broadcast for OpenSearch indexing
    Phoenix.PubSub.broadcast(Hybridsocial.PubSub, "posts", {:post_created, post})

    # Fan direct posts out to the recipients' SSE streams so the
    # Direct tab live-updates without a refresh.
    broadcast_direct_post_to_participants(post)

    # Live-feed streaming: push the serialized post to the public
    # timeline topic (explore/local/global) AND to every accepted
    # follower's `user:<id>` topic (home timeline). Without this the
    # "N new posts" banner never ticks — the streaming consumers
    # were wired but no producer was calling them.
    serialized = HybridsocialWeb.Serializers.PostSerializer.serialize(post, [])
    Hybridsocial.Streaming.broadcast_post(serialized)

    # Federate public/followers-visible posts to remote followers.
    # Direct + private posts stay local unless sent as a DM; they
    # go through a different delivery path (inbox push for
    # mentioned remote users only).
    maybe_federate_create(post)

    Hybridsocial.Moderation.fire_webhook("post.created", %{
      id: post.id,
      author_id: post.identity_id,
      author_handle: post.identity && post.identity.handle,
      visibility: post.visibility,
      content: post.content,
      created_at: post.inserted_at
    })

    post
  end

  # Fires a Create{Note} activity out to the post author's remote
  # followers via the federation publisher. Runs async in the delivery
  # task supervisor so slow / dead peers don't hold up the insert.
  # Private-visibility + direct posts don't fan out publicly —
  # Publisher.publish handles the audience scoping based on `to`/`cc`.
  defp maybe_federate_create(%Post{visibility: vis} = post)
       when vis in ["public", "followers", "unlisted", "direct"] do
    if post.identity && post.identity.private_key do
      Hybridsocial.Federation.deliver_async(fn ->
        # Direct posts need their mentions preloaded so the activity
        # builder can target each recipient explicitly; other
        # visibilities fan out via followers/Public addressing and
        # don't need them.
        post =
          if vis == "direct",
            do: Hybridsocial.Repo.preload(post, mentions: :identity),
            else: post

        activity = Hybridsocial.Federation.ActivityBuilder.build_create(post)
        Hybridsocial.Federation.Publisher.publish(activity, post.identity)
      end)
    end

    :ok
  end

  defp maybe_federate_create(_post), do: :ok

  @doc """
  Pushes a newly-created direct post to the SSE topic for every local
  participant (author + mentioned identities). The frontend's
  chat-stream already subscribes to `user:<id>`, so adding the
  `direct.new_post` event there lets the profile's Direct tab
  append without polling. No-op for non-direct visibilities — the
  home timeline has its own broadcast path.
  """
  def broadcast_direct_post_to_participants(%Post{visibility: "direct"} = post) do
    post = Repo.preload(post, [:identity, mentions: :identity])

    recipient_ids =
      [post.identity_id | Enum.map(post.mentions, & &1.identity_id)]
      |> Enum.uniq()
      |> Enum.filter(&local_identity?/1)

    # Serialize once; every recipient gets the same payload. No
    # viewer-specific fields here (reactions, bookmarks etc. are
    # fetched on demand when the UI renders the bubble).
    serialized =
      HybridsocialWeb.Serializers.PostSerializer.serialize(post, current_identity_id: nil)

    for rid <- recipient_ids do
      Phoenix.PubSub.broadcast(
        Hybridsocial.PubSub,
        "user:#{rid}",
        %{event: "direct.new_post", payload: serialized}
      )
    end

    :ok
  end

  def broadcast_direct_post_to_participants(_post), do: :ok

  # Accepts either a loaded `%Identity{}` or a binary id. The two
  # clauses are grouped so credo's "same name/arity should be
  # contiguous" warning stays quiet even though callers mix both
  # shapes.
  defp local_identity?(%Hybridsocial.Accounts.Identity{} = identity),
    do: Hybridsocial.Federation.LocalUrl.local_identity?(identity)

  defp local_identity?(identity_id) when is_binary(identity_id) do
    case Repo.get(Hybridsocial.Accounts.Identity, identity_id) do
      %Hybridsocial.Accounts.Identity{} = id ->
        Hybridsocial.Federation.LocalUrl.local_identity?(id)

      _ ->
        false
    end
  end

  # Populates `post_mentions` for a locally-authored post. Sources:
  #   1. Explicit `mentioned_identity_ids` attr — set by flows that
  #      know the audience before composing (e.g. the DM→direct-post
  #      fallback when a user "DMs" a Mastodon account).
  #   2. `@handle` / `@handle@domain` patterns in the post content —
  #      resolved through Accounts so the mention points at the same
  #      identity row the serializer renders.
  defp persist_local_mentions(%Post{id: post_id, content: content}, attrs) do
    explicit_ids =
      attrs
      |> (&(Map.get(&1, "mentioned_identity_ids") || Map.get(&1, :mentioned_identity_ids) || [])).()
      |> List.wrap()

    parsed_ids =
      content
      |> extract_handles()
      |> Enum.map(&resolve_handle_to_identity_id/1)
      |> Enum.reject(&is_nil/1)

    ids = Enum.uniq(explicit_ids ++ parsed_ids)

    for identity_id <- ids do
      %Hybridsocial.Social.PostMention{}
      |> Hybridsocial.Social.PostMention.changeset(%{
        post_id: post_id,
        identity_id: identity_id
      })
      |> Repo.insert(on_conflict: :nothing)
    end

    ids
  end

  defp extract_handles(content), do: Hybridsocial.Federation.LocalUrl.parse_mentions(content)

  @doc """
  The new-account gates (#67) for a post written by `identity`, the person
  acting: no links, and a direct post may only reach people who follow them.
  `:ok`, `{:error, :trust_links_not_allowed}` or `{:error, :trust_dm_not_allowed}`.
  `nil` (an internal caller with no acting person) is never gated.
  """
  def check_trust_gates(nil, _attrs), do: :ok

  def check_trust_gates(identity, attrs) do
    texts = [attr(attrs, "content"), attr(attrs, "spoiler_text"), attr(attrs, "options")]

    with :ok <- Hybridsocial.Accounts.Trust.check_links(identity, texts) do
      if attr(attrs, "visibility") == "direct" do
        Hybridsocial.Accounts.Trust.check_dm(identity, direct_recipient_ids(attrs))
      else
        :ok
      end
    end
  end

  defp attr(attrs, key), do: Map.get(attrs, key)

  # The same recipients `persist_local_mentions/2` will record.
  defp direct_recipient_ids(attrs) do
    explicit = attrs |> attr("mentioned_identity_ids") |> List.wrap()

    parsed =
      attrs
      |> attr("content")
      |> extract_handles()
      |> Enum.map(&resolve_handle_to_identity_id/1)
      |> Enum.reject(&is_nil/1)

    Enum.uniq(explicit ++ parsed)
  end

  # Resolve `@handle` with no explicit domain: must be a local identity.
  defp resolve_handle_to_identity_id({handle, domain}) do
    case Hybridsocial.Federation.LocalUrl.resolve_mention(handle, domain) do
      %Hybridsocial.Accounts.Identity{id: id} -> id
      nil -> nil
    end
  end

  # Attaches the listed media files to the post. Only media owned by the post's
  # author and not already attached to another post are linked; anything else
  # is silently skipped so a bad media_id can't fail a post insert.
  defp attach_media(_post, [], _uploader_id), do: :ok
  defp attach_media(_post, nil, _uploader_id), do: :ok

  # `uploader_id` is the human who uploaded the media (and is authoring the
  # post) — NOT post.identity_id, which is the page when posting as a page.
  defp attach_media(%Post{id: post_id}, media_ids, uploader_id)
       when is_list(media_ids) do
    query =
      from m in Hybridsocial.Media.MediaFile,
        where:
          m.id in ^media_ids and
            m.identity_id == ^uploader_id and
            is_nil(m.deleted_at) and
            is_nil(m.post_id)

    Repo.update_all(query, set: [post_id: post_id, updated_at: DateTime.utc_now()])
    :ok
  end

  # Reconcile a post's media to match the supplied id list:
  # - Anything currently attached but missing from the list is
  #   soft-deleted (deleted_at = now). The MediaPurgeWorker hard-
  #   deletes rows where deleted_at < now - 7 days, giving the
  #   author a window to undo.
  # - Anything new in the list that the author owns and isn't
  #   attached to a different post gets attached to this one.
  # The order matters: detach first so a media row that's both
  # "kept" and would re-attach doesn't land in the wrong post_id.
  defp reconcile_media(%Post{id: post_id}, desired_ids, uploader_id)
       when is_list(desired_ids) do
    now = DateTime.utc_now()

    current =
      Repo.all(
        from m in Hybridsocial.Media.MediaFile,
          where: m.post_id == ^post_id and is_nil(m.deleted_at),
          select: m.id
      )

    desired_set = MapSet.new(desired_ids)
    current_set = MapSet.new(current)
    to_remove = MapSet.difference(current_set, desired_set) |> MapSet.to_list()
    to_add = MapSet.difference(desired_set, current_set) |> MapSet.to_list()

    if to_remove != [] do
      from(m in Hybridsocial.Media.MediaFile,
        where: m.id in ^to_remove and m.post_id == ^post_id
      )
      |> Repo.update_all(set: [deleted_at: now, updated_at: now])
    end

    if to_add != [] do
      attach_media(%Post{id: post_id}, to_add, uploader_id)
    end

    :ok
  end

  @doc """
  Resolves root_id from parent chain. If the post has a parent_id but no root_id,
  walks up the parent chain to find the root post.
  """
  def maybe_resolve_root_id(%{"parent_id" => parent_id} = attrs)
      when is_binary(parent_id) and parent_id != "" do
    if Map.get(attrs, "root_id") do
      attrs
    else
      case Repo.get(Post, parent_id) do
        nil ->
          attrs

        parent ->
          root_id = parent.root_id || parent.id
          Map.put(attrs, "root_id", root_id)
      end
    end
  end

  def maybe_resolve_root_id(attrs), do: attrs

  @doc """
  If this post is a reply to a mirrored remote post, copy the parent's
  `ap_id` into our `parent_ap_id` so our outbound Create carries the
  ORIGINAL remote URL in `inReplyTo` — not our local mirror URL, which
  the remote wouldn't recognize. Without this, replies from our users
  to federated posts never thread properly on the origin instance.
  """
  def maybe_resolve_parent_ap_id(%{"parent_id" => parent_id} = attrs)
      when is_binary(parent_id) and parent_id != "" do
    if Map.get(attrs, "parent_ap_id") do
      attrs
    else
      case Repo.get(Post, parent_id) do
        %Post{ap_id: ap_id} when is_binary(ap_id) ->
          Map.put(attrs, "parent_ap_id", ap_id)

        _ ->
          attrs
      end
    end
  end

  def maybe_resolve_parent_ap_id(attrs), do: attrs

  def edit_post(post_id, identity_id, attrs, identity \\ nil) do
    with {:ok, post} <- get_owned_post(post_id, identity_id),
         :ok <- validate_premium_emojis(attrs["content"], identity),
         :ok <- check_trust_gates(identity, Map.put(attrs, "visibility", post.visibility)) do
      limits =
        if identity do
          TierLimits.limits_for(identity)
        else
          TierLimits.limits_for_tier("verified_pro")
        end

      # Re-render content_html with the author's tier markdown level, exactly
      # like create_post does. Without this, edit_changeset/generate_content_html
      # falls back to a plaintext sanitize and silently strips the post's
      # markdown formatting on every edit. Pre-setting content_html here means
      # generate_content_html keeps it as-is.
      attrs =
        case attrs["content"] do
          content when is_binary(content) ->
            level = resolve_markdown_level(attrs, limits)
            Map.put(attrs, "content_html", maybe_render_content_html(content, level))

          _ ->
            attrs
        end

      revision_number = get_next_revision_number(post_id)

      # A media-bearing post (captioned image is stored as post_type
      # "text") must not require content on edit. Use the supplied
      # media_ids when the editor sent them, otherwise the post's
      # existing attachments.
      has_media? =
        case media_ids_from_attrs(attrs) do
          [] -> post_has_media?(post.id)
          ids -> ids != []
        end

      Ecto.Multi.new()
      |> Ecto.Multi.insert(:revision, fn _ ->
        %PostRevision{}
        |> PostRevision.changeset(%{
          post_id: post.id,
          content: post.content,
          content_html: post.content_html,
          edited_at: post.edited_at || post.inserted_at,
          revision_number: revision_number
        })
      end)
      |> Ecto.Multi.update(:post, fn _ ->
        Post.edit_changeset(post, attrs,
          char_limit: limits[:char_limit] || 5000,
          has_media: has_media?
        )
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{post: post}} ->
          if post.content, do: extract_and_link_hashtags(post)

          # Reconcile media attachments if the editor supplied a
          # media_ids list. Sticking to "supplied → reconcile, absent
          # → leave alone" so legacy callers that only edit text don't
          # accidentally detach attachments.
          case media_ids_from_attrs(attrs) do
            [] -> :ok
            # Match media by the human editor (who uploaded it), not the post's
            # identity, so editing a page post's media works (page_id != human).
            ids -> reconcile_media(post, ids, uploader_id(identity, identity_id))
          end

          # Mentions can change between versions. For a direct post
          # that means access changes: someone removed from the
          # mention list should lose read access, and a newly added
          # mention needs to be granted and notified. resync_post_mentions
          # returns the union of old + new identity IDs so the Update
          # activity can be federated wide enough to reach the
          # former audience (so their copy updates/disappears).
          {new_ids, removed_ids} = resync_post_mentions(post, attrs)

          if new_ids != [] do
            notify_mentions(post, new_ids)
          end

          Phoenix.PubSub.broadcast(Hybridsocial.PubSub, "posts", {:post_updated, post})

          # Per-post topic, consumed by the composer's live-edit
          # SSE stream so a user replying to this post sees the
          # "edited" indicator within seconds instead of on next
          # refresh.
          Phoenix.PubSub.broadcast(
            Hybridsocial.PubSub,
            "post:#{post.id}",
            %{event: "edit", payload: %{id: post.id, edited_at: post.edited_at}}
          )

          # Federate Update to the post's new audience, plus removed
          # recipients so their mirror gets the new content (which
          # drops them from the addressing). Mastodon-class peers
          # drop inbox messages from actors they're not "seeing" the
          # post via, so this is best-effort cleanup.
          federate_update(post, removed_ids)

          {:ok, post}

        {:error, :post, changeset, _} ->
          {:error, changeset}

        {:error, :revision, changeset, _} ->
          {:error, changeset}
      end
    end
  end

  # Diff old post_mentions against the new content's resolved mentions
  # and reconcile. Returns `{new_ids, removed_ids}` so callers can
  # both notify the additions and widen Update federation to include
  # the removals for one more delivery.
  defp resync_post_mentions(%Post{id: post_id, content: content}, _attrs) do
    import Ecto.Query

    current =
      Repo.all(
        from pm in Hybridsocial.Social.PostMention,
          where: pm.post_id == ^post_id,
          select: pm.identity_id
      )

    desired_ids =
      content
      |> (fn c -> Hybridsocial.Federation.LocalUrl.parse_mentions(c) end).()
      |> Enum.map(fn {h, d} ->
        case Hybridsocial.Federation.LocalUrl.resolve_mention(h, d) do
          %Hybridsocial.Accounts.Identity{id: id} -> id
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    to_add = desired_ids -- current
    to_remove = current -- desired_ids

    for identity_id <- to_add do
      %Hybridsocial.Social.PostMention{}
      |> Hybridsocial.Social.PostMention.changeset(%{
        post_id: post_id,
        identity_id: identity_id
      })
      |> Repo.insert(on_conflict: :nothing)
    end

    if to_remove != [] do
      Repo.delete_all(
        from pm in Hybridsocial.Social.PostMention,
          where: pm.post_id == ^post_id and pm.identity_id in ^to_remove
      )
    end

    {to_add, to_remove}
  end

  defp federate_update(%Post{visibility: vis} = post, extra_recipient_ids)
       when vis in ["public", "unlisted", "followers", "direct"] do
    post = Repo.preload(post, [:identity, mentions: :identity])

    if post.identity && post.identity.private_key do
      Hybridsocial.Federation.deliver_async(fn ->
        activity = Hybridsocial.Federation.ActivityBuilder.build_update(post)
        activity = widen_addressing(activity, extra_recipient_ids)
        Hybridsocial.Federation.Publisher.publish(activity, post.identity)
      end)
    end

    :ok
  end

  defp federate_update(_post, _extra), do: :ok

  # For a direct post, append removed recipients' ap_actor_urls to the
  # Update's `to` list so their side gets the new version / drops the
  # old one. No-op for other visibilities since the audience is
  # collection-based, not per-recipient.
  defp widen_addressing(activity, []), do: activity

  defp widen_addressing(%{"object" => %{"type" => "Note"} = note} = activity, extra_ids) do
    extra_urls =
      Hybridsocial.Repo.all(
        from i in Hybridsocial.Accounts.Identity,
          where: i.id in ^extra_ids and not is_nil(i.ap_actor_url),
          select: i.ap_actor_url
      )

    existing = List.wrap(activity["to"])
    widened = Enum.uniq(existing ++ extra_urls)

    activity
    |> Map.put("to", widened)
    |> Map.put("object", Map.put(note, "to", widened))
  end

  defp widen_addressing(activity, _), do: activity

  defp notify_mentions(%Post{} = post, identity_ids) do
    Hybridsocial.Notifications.notify_mention(post.identity_id, post, identity_ids)
  end

  defp notify_reply_to_parent(%Post{parent_id: parent_id} = post)
       when is_binary(parent_id) do
    case get_post(parent_id) do
      nil ->
        :ok

      %Post{} = parent ->
        Hybridsocial.Notifications.notify_reply(post.identity_id, post, parent)
    end
  end

  defp notify_reply_to_parent(_), do: :ok

  defp notify_quote(%Post{quote_id: quote_id} = post) when is_binary(quote_id) do
    case get_post(quote_id) do
      nil ->
        :ok

      %Post{identity_id: quoted_author_id} ->
        Hybridsocial.Notifications.create_notification(%{
          recipient_id: quoted_author_id,
          actor_id: post.identity_id,
          type: "quote",
          target_type: "post",
          target_id: post.id
        })
    end
  end

  defp notify_quote(_), do: :ok

  def delete_post(post_id, identity_id) do
    with {:ok, post} <- get_owned_post(post_id, identity_id) do
      case post |> Post.soft_delete_changeset() |> Repo.update() do
        {:ok, deleted} ->
          # Mirror the increment in create_post: when a reply is
          # deleted, drop the parent's reply_count so the bubble in
          # the UI stays accurate. Floor at 0 in case create-time
          # increments and delete-time decrements ever fall out of
          # sync (e.g. a partial migration leaves an orphaned row).
          if deleted.parent_id do
            decrement_reply_count(deleted.parent_id)
          end

          Phoenix.PubSub.broadcast(Hybridsocial.PubSub, "posts", {:post_deleted, post_id})
          federate_delete(deleted)

          Hybridsocial.Moderation.fire_webhook("post.deleted", %{
            id: deleted.id,
            author_id: deleted.identity_id,
            deleted_at: deleted.deleted_at
          })

          {:ok, deleted}

        error ->
          error
      end
    end
  end

  # Fan a Delete activity out to the post's original audience so
  # remote mirrors disappear too. Only for locally-authored posts
  # that actually federated — remote-origin posts (mirrors on our
  # side) shouldn't emit Deletes; the peer would reject them for
  # origin mismatch anyway.
  defp federate_delete(%Post{} = post) do
    post = Repo.preload(post, [:identity, mentions: :identity])

    cond do
      post.identity == nil ->
        :ok

      not local_identity?(post.identity) ->
        :ok

      post.visibility not in ["public", "unlisted", "followers", "direct"] ->
        :ok

      true ->
        Hybridsocial.Federation.deliver_async(fn ->
          activity = Hybridsocial.Federation.ActivityBuilder.build_delete(post)
          Hybridsocial.Federation.Publisher.publish(activity, post.identity)
        end)

        :ok
    end
  end

  # --- Post queries ---

  def get_post(id) do
    Post
    |> where([p], is_nil(p.deleted_at))
    |> Repo.get(id)
  end

  def get_post!(id) do
    Post
    |> where([p], is_nil(p.deleted_at))
    |> Repo.get!(id)
  end

  def get_post_with_context(id) do
    Post
    |> where([p], is_nil(p.deleted_at))
    |> Repo.get(id)
    |> case do
      nil -> nil
      post -> Repo.preload(post, [:identity, :parent, :quote, poll: :options])
    end
  end

  @doc """
  Returns the post only if the viewer is allowed to read it. Direct
  posts require the viewer to be the author or a recorded mention;
  followers-only posts require follower status; public/unlisted are
  readable by anyone (auth still enforced at the controller level
  when a DM-free surface is needed). `nil` viewer means anonymous.
  """
  def get_post_for_viewer(id, viewer_identity_id) do
    case get_post(id) do
      nil -> nil
      post -> if viewer_can_read?(post, viewer_identity_id), do: post, else: nil
    end
  end

  @doc """
  Same as `get_post_for_viewer/2` but preloads the context
  associations used by the AP serializer + UI.
  """
  def get_post_with_context_for_viewer(id, viewer_identity_id) do
    case get_post_with_context(id) do
      nil -> nil
      post -> if viewer_can_read?(post, viewer_identity_id), do: post, else: nil
    end
  end

  @doc """
  Predicate form of the viewer access check. Used by controllers and
  activity handlers that already have the post in hand.
  """
  def viewer_can_read?(post, viewer_id)

  def viewer_can_read?(
        %Post{visibility: vis, identity_id: author_id, id: post_id} = post,
        viewer_id
      ) do
    cond do
      # A locked account is private to anyone not logged in, even for posts marked
      # public. See Accounts.hidden_from_viewer?/2.
      is_nil(viewer_id) and author_locked?(post) ->
        false

      vis in ["public", "unlisted"] ->
        true

      is_nil(viewer_id) ->
        false

      viewer_id == author_id ->
        true

      vis == "direct" ->
        mentioned?(post_id, viewer_id)

      vis == "followers" ->
        # Followers-only: viewer must follow the author.
        Hybridsocial.Social.following?(viewer_id, author_id)

      vis == "list" ->
        list_member?(post.list_id, viewer_id)

      vis == "group" ->
        group_member?(post.group_id, viewer_id)

      true ->
        false
    end
  end

  def viewer_can_read?(_, _), do: false

  defp author_locked?(%Post{identity: %Hybridsocial.Accounts.Identity{is_locked: locked}}),
    do: locked

  defp author_locked?(%Post{identity_id: author_id}) do
    Repo.exists?(
      from i in Hybridsocial.Accounts.Identity,
        where: i.id == ^author_id and i.is_locked == true
    )
  end

  defp list_member?(nil, _viewer_id), do: false

  defp list_member?(list_id, viewer_id) do
    Repo.exists?(
      from lm in Hybridsocial.Social.ListMember,
        where: lm.list_id == ^list_id and lm.target_identity_id == ^viewer_id
    )
  end

  defp group_member?(nil, _viewer_id), do: false

  # Delegates to `Groups.member?/2`, which filters `status == :approved`.
  # This used to test only (group_id, identity_id), so every non-approved row
  # still satisfied it — a **banned** member kept read access to the group's
  # posts, as did a pending or rejected applicant to a private group. The
  # membership row survives a ban by design (it's what records the ban), so
  # the status filter is the whole check.
  defp group_member?(group_id, viewer_id) when is_binary(viewer_id) do
    Hybridsocial.Groups.member?(group_id, viewer_id)
  end

  defp group_member?(_group_id, _viewer_id), do: false

  defp mentioned?(post_id, identity_id) do
    Repo.exists?(
      from pm in Hybridsocial.Social.PostMention,
        where: pm.post_id == ^post_id and pm.identity_id == ^identity_id
    )
  end

  @doc """
  Fetch many posts in one round-trip. Accepts up to `@max_batch_ids`
  IDs; extras are silently dropped. Missing / soft-deleted IDs are
  skipped (no 404 — the caller knows which IDs they asked for).
  """
  @max_batch_ids 100
  def list_posts_by_ids(ids) when is_list(ids) do
    clean_ids =
      ids
      |> Enum.filter(&is_binary/1)
      |> Enum.take(@max_batch_ids)

    case clean_ids do
      [] ->
        []

      ids ->
        Post
        |> where([p], p.id in ^ids)
        |> where([p], is_nil(p.deleted_at))
        |> Repo.all()
        |> Repo.preload([:identity, :quote, poll: :options])
    end
  end

  def get_thread(post_id) do
    case get_post(post_id) do
      nil ->
        {:error, :not_found}

      post ->
        # Walk up the parent chain to get true ancestors
        ancestors = collect_ancestors(post, [])

        # Descendants: direct replies to this post, and their children
        descendants =
          Post
          |> where([p], is_nil(p.deleted_at))
          |> where([p], p.parent_id == ^post_id or p.root_id == ^post_id)
          |> where([p], p.id != ^post.id)
          |> order_by([p], asc: p.published_at)
          |> Repo.all()
          |> Repo.preload(:identity)

        {:ok, %{ancestors: ancestors, descendants: descendants}}
    end
  end

  # Walk up parent chain to collect true ancestors (max 20 to prevent loops)
  # Includes soft-deleted posts so they render as tombstones
  defp collect_ancestors(%{parent_id: nil}, acc), do: Enum.reverse(acc)
  defp collect_ancestors(_, acc) when length(acc) >= 20, do: Enum.reverse(acc)

  defp collect_ancestors(%{parent_id: parent_id}, acc) when is_binary(parent_id) do
    case Repo.get(Post, parent_id) do
      nil ->
        Enum.reverse(acc)

      parent ->
        parent = Repo.preload(parent, :identity)
        collect_ancestors(parent, [parent | acc])
    end
  end

  defp collect_ancestors(_, acc), do: Enum.reverse(acc)

  def get_revisions(post_id) do
    PostRevision
    |> where([r], r.post_id == ^post_id)
    |> order_by([r], asc: r.revision_number)
    |> Repo.all()
  end

  # --- Reactions ---

  # Reacting to a group-scoped post requires approved membership — a banned
  # member could otherwise keep reacting to the group's content indefinitely.
  #
  # Deliberately narrow: this checks group membership only, not general
  # readability via `viewer_can_read?/2`. `react/4` is also the federation
  # inbox's entry point for remote Likes (inbox.ex), and gating those on a
  # local readability predicate would drop legitimate remote reactions. A
  # remote actor who *is* an approved member still passes.
  defp check_group_reaction_allowed(%Post{group_id: gid, visibility: "group"}, identity_id)
       when is_binary(gid) do
    if Hybridsocial.Groups.can_do_in_group?(gid, identity_id, :react),
      do: :ok,
      else: {:error, :group_forbidden}
  end

  defp check_group_reaction_allowed(_post, _identity_id), do: :ok

  def react(post_id, identity_id, type, opts \\ []) do
    target_media_id = Keyword.get(opts, :target_media_id)

    with {:ok, post} <- get_existing_post(post_id),
         :ok <- check_group_reaction_allowed(post, identity_id),
         :ok <- validate_target_media(post_id, target_media_id) do
      case get_existing_reaction(post_id, identity_id, target_media_id) do
        nil ->
          %Reaction{}
          |> Reaction.changeset(
            %{
              post_id: post_id,
              identity_id: identity_id,
              type: type,
              target_media_id: target_media_id
            },
            opts
          )
          |> Repo.insert()
          |> case do
            {:ok, reaction} ->
              # Only the post-level reaction bumps the counter on the
              # post — per-image reactions are tallied in the
              # PostSerializer's `media_reaction_counts` map. Same
              # split as `media_reply_counts`.
              if is_nil(target_media_id) do
                update_reaction_count(post_id, 1)
              end

              # Bell the post's author. Self-reactions are filtered
              # out by create_notification, so we don't guard here.
              Hybridsocial.Notifications.notify_reaction(identity_id, post)
              maybe_federate_reaction(post, identity_id, type)
              {:ok, reaction}

            error ->
              error
          end

        existing ->
          # Reaction already exists — either same type (idempotent
          # no-op) or different type (updating emoji). Re-notifying
          # would double-bell, so skip. Still federate the new type
          # so the remote peer sees the swap (Like → 😢, etc).
          case existing |> Reaction.changeset(%{type: type}, opts) |> Repo.update() do
            {:ok, _reaction} = ok ->
              if existing.type != type do
                maybe_federate_reaction(post, identity_id, type)
              end

              ok

            error ->
              error
          end
      end
    end
  end

  # Per-image reaction target must belong to the same post the
  # reaction is attached to — same rule we already enforce on
  # per-image replies via `check_target_media`.
  defp validate_target_media(_post_id, nil), do: :ok

  defp validate_target_media(post_id, media_id) when is_binary(media_id) do
    case Repo.one(
           from m in Hybridsocial.Media.MediaFile,
             where: m.id == ^media_id and is_nil(m.deleted_at),
             select: m.post_id
         ) do
      nil -> {:error, :target_media_not_found}
      ^post_id -> :ok
      _ -> {:error, :target_media_mismatch}
    end
  end

  defp validate_target_media(_post_id, _other), do: {:error, :target_media_invalid}

  # Push a Like (for type=="like") or EmojiReact activity to the
  # remote author so reactions on federated posts actually reach the
  # origin. No-op for purely local posts — the bell + counter already
  # surface the reaction inside our instance.
  defp maybe_federate_reaction(%Post{} = post, identity_id, type) do
    # Even when the post itself is local we still federate the
    # reaction — every remote instance that mirrored the post via
    # Follow needs the Like/EmojiReact activity in order to update
    # the cached reaction count. The activity builder pre-computes
    # the remote audience, so a post with no remote followers and no
    # remote mentions ends up with an empty recipient set and the
    # Publisher noops naturally.
    post = Repo.preload(post, [:identity, mentions: :identity])

    if post.identity, do: spawn_federate_reaction(post, identity_id, type), else: :ok
  end

  defp spawn_federate_reaction(post, identity_id, type) do
    Hybridsocial.Federation.deliver_async(fn ->
      identity = Repo.get(Hybridsocial.Accounts.Identity, identity_id)

      if identity && is_binary(identity.private_key) do
        activity =
          case reaction_emoji_for(type) do
            nil ->
              Hybridsocial.Federation.ActivityBuilder.build_like(identity, post)

            emoji ->
              Hybridsocial.Federation.ActivityBuilder.build_emoji_react(identity, post, emoji)
          end

        Hybridsocial.Federation.Publisher.publish(activity, identity)
      end
    end)
  end

  # Map our internal reaction type to a Unicode emoji for the
  # outbound `content` field on EmojiReact. `like` → no content,
  # everything else carries the corresponding glyph. Mirrors the
  # ingest map in Federation.ActivityMapper so a round trip
  # love → ❤️ → love stays stable.
  defp reaction_emoji_for("like"), do: nil
  defp reaction_emoji_for("love"), do: "❤️"
  defp reaction_emoji_for("wow"), do: "🤯"
  defp reaction_emoji_for("care"), do: "🥰"
  defp reaction_emoji_for("angry"), do: "😡"
  defp reaction_emoji_for("sad"), do: "😢"
  defp reaction_emoji_for("lol"), do: "😂"
  defp reaction_emoji_for(_), do: nil

  def unreact(post_id, identity_id, target_media_id \\ nil) do
    case get_existing_reaction(post_id, identity_id, target_media_id) do
      nil ->
        {:error, :not_found}

      reaction ->
        case Repo.delete(reaction) do
          {:ok, deleted} ->
            # Mirror the bump rule from `react/4` — only post-level
            # reactions move the post's `reaction_count`. Per-image
            # reactions live in the serializer's media_reaction_counts
            # map and don't need a counter column.
            if is_nil(deleted.target_media_id) do
              update_reaction_count(post_id, -1)
            end

            # Tell the remote peer to drop the like/emoji-react if
            # the post lives there. Best-effort; the reaction is
            # already gone locally.
            with {:ok, post} <- get_existing_post(post_id) do
              maybe_federate_unreact(post, identity_id, deleted.type)
            end

            {:ok, deleted}

          error ->
            error
        end
    end
  end

  defp maybe_federate_unreact(%Post{} = post, identity_id, type) do
    post = Repo.preload(post, [:identity, mentions: :identity])

    if post.identity, do: spawn_federate_unreact(post, identity_id, type), else: :ok
  end

  defp spawn_federate_unreact(post, identity_id, type) do
    Hybridsocial.Federation.deliver_async(fn ->
      identity = Repo.get(Hybridsocial.Accounts.Identity, identity_id)

      if identity && is_binary(identity.private_key) do
        inner =
          case reaction_emoji_for(type) do
            nil ->
              Hybridsocial.Federation.ActivityBuilder.build_like(identity, post)

            emoji ->
              Hybridsocial.Federation.ActivityBuilder.build_emoji_react(identity, post, emoji)
          end

        # Wrap in Undo so the remote peer drops the prior reaction.
        # Reusing the inner activity verbatim keeps the `id` matched
        # to what was originally delivered, which is what Mastodon's
        # Undo handler keys off. Preserve the cc so the Undo reaches
        # every peer that received the original Like.
        undo = %{
          "@context" => "https://www.w3.org/ns/activitystreams",
          "id" => inner["id"] <> "/undo",
          "type" => "Undo",
          "actor" => inner["actor"],
          "to" => inner["to"],
          "cc" => inner["cc"] || [],
          "object" => inner
        }

        Hybridsocial.Federation.Publisher.publish(undo, identity)
      end
    end)
  end

  def get_reactions(post_id) do
    Reaction
    |> where([r], r.post_id == ^post_id)
    |> order_by([r], desc: r.inserted_at)
    |> Repo.all()
    |> Repo.preload(:identity)
  end

  # --- Boosts ---

  def boost(post_id, identity_id) do
    with {:ok, post} <- get_existing_post(post_id),
         :ok <- check_boost_allowed(post, identity_id) do
      %Boost{}
      |> Boost.changeset(%{post_id: post_id, identity_id: identity_id})
      |> Repo.insert()
      |> case do
        {:ok, boost} ->
          update_boost_count(post_id, 1)
          Hybridsocial.Notifications.notify_boost(identity_id, post)
          {:ok, boost}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  # Boosting has two gates: the viewer must be able to read the post
  # in the first place (else it 404s, matching `show`), and the post
  # must be boostable — direct/followers posts aren't, because a
  # boost fans them out to followers which violates the original
  # audience.
  defp check_boost_allowed(post, identity_id) do
    cond do
      not viewer_can_read?(post, identity_id) ->
        {:error, :not_found}

      post.visibility in ["direct", "followers", "list", "group"] ->
        {:error, :boost_not_allowed}

      true ->
        :ok
    end
  end

  def unboost(post_id, identity_id) do
    case get_existing_boost(post_id, identity_id) do
      nil ->
        {:error, :not_found}

      boost ->
        case Repo.delete(boost) do
          {:ok, boost} ->
            update_boost_count(post_id, -1)
            {:ok, boost}

          error ->
            error
        end
    end
  end

  # --- Quote posts ---

  def quote_post(identity_id, quoted_post_id, attrs) do
    with {:ok, _quoted} <- get_existing_post(quoted_post_id) do
      attrs
      |> Map.put("quote_id", quoted_post_id)
      |> then(&create_post(identity_id, &1))
    end
  end

  # --- Pin/Unpin ---

  def reacted_posts(identity_id, opts \\ []) do
    max_id = Keyword.get(opts, :max_id)

    # Get post IDs from reactions, ordered by reaction time
    reaction_query =
      Reaction
      |> where([r], r.identity_id == ^identity_id)
      |> order_by([r], desc: r.inserted_at)
      |> select([r], r.post_id)
      |> limit(20)

    reaction_query =
      if max_id, do: where(reaction_query, [r], r.id < ^max_id), else: reaction_query

    post_ids = Repo.all(reaction_query)

    Post
    |> where([p], p.id in ^post_ids and is_nil(p.deleted_at))
    |> preload([:identity, :quote])
    |> Repo.all()
    |> Enum.sort_by(fn p -> Enum.find_index(post_ids, &(&1 == p.id)) end)
  end

  @doc """
  Number of published, non-deleted posts authored by an identity.

  Feeds Mastodon's non-null `statuses_count` on profile responses. Only used
  on single-account endpoints — embedding it in a follower list would be one
  count query per row.
  """
  def published_count(identity_id) do
    Post
    |> where([p], p.identity_id == ^identity_id)
    |> where([p], is_nil(p.deleted_at) and not is_nil(p.published_at))
    |> Repo.aggregate(:count)
  end

  @doc """
  Counts posts pinned to a given scope.

      pinned_count({:profile, identity_id}) — profile-scoped pins for the author.
                                              Excludes group/page posts so a
                                              group/page pin doesn't eat the
                                              author's tier allowance.
      pinned_count({:group,   group_id})    — pinned posts in the group.
      pinned_count({:page,    page_id})     — pinned posts on the page.

  Legacy single-arg form (`pinned_count(identity_id)`) keeps the old
  profile-only semantics for callers that haven't migrated.
  """
  def pinned_count({:profile, identity_id}) do
    Post
    |> where(
      [p],
      p.identity_id == ^identity_id and p.is_pinned == true and is_nil(p.deleted_at) and
        is_nil(p.group_id) and is_nil(p.page_id)
    )
    |> Repo.aggregate(:count)
  end

  def pinned_count({:group, group_id}) do
    Post
    |> where(
      [p],
      p.group_id == ^group_id and p.is_pinned == true and is_nil(p.deleted_at)
    )
    |> Repo.aggregate(:count)
  end

  def pinned_count({:page, page_id}) do
    Post
    |> where(
      [p],
      p.page_id == ^page_id and p.is_pinned == true and is_nil(p.deleted_at)
    )
    |> Repo.aggregate(:count)
  end

  def pinned_count(identity_id) when is_binary(identity_id) do
    pinned_count({:profile, identity_id})
  end

  @doc """
  Returns the pin scope for a post — `{:group, id}`, `{:page, id}`, or
  `{:profile, identity_id}`. Used to route pin-permission and
  pin-count checks; mirrors the precedence the timelines use when
  surfacing the post (group > page > profile).
  """
  def pin_scope(%Post{group_id: gid}) when is_binary(gid), do: {:group, gid}
  def pin_scope(%Post{page_id: pid}) when is_binary(pid), do: {:page, pid}
  def pin_scope(%Post{identity_id: iid}), do: {:profile, iid}

  @doc """
  Pins a post. Permission depends on where the post lives:

    * group post → caller must be group :owner or :admin
    * page post  → caller must pass `Pages.can_edit?/2`
                   (parent owner, org owner, admin, or editor)
    * profile    → caller must be the post author

  Returns `{:ok, post}` on success, `{:error, :not_found}` if missing,
  `{:error, :forbidden}` on permission failure.
  """
  def pin_post(post_id, actor_identity_id) do
    set_pinned(post_id, actor_identity_id, true)
  end

  def unpin_post(post_id, actor_identity_id) do
    set_pinned(post_id, actor_identity_id, false)
  end

  defp set_pinned(post_id, actor_identity_id, value) do
    case fetch_post(post_id) do
      nil ->
        {:error, :not_found}

      %Post{} = post ->
        if can_pin?(post, actor_identity_id) do
          post
          |> Ecto.Changeset.change(is_pinned: value)
          |> Repo.update()
        else
          {:error, :forbidden}
        end
    end
  end

  defp fetch_post(post_id) do
    Post
    |> where([p], p.id == ^post_id and is_nil(p.deleted_at))
    |> Repo.one()
  end

  # Authorization for pin/unpin. Intentionally not exposed as a public
  # helper — callers should go through `pin_post/2` so the scope
  # semantics stay in one place.
  defp can_pin?(%Post{} = post, actor_identity_id) do
    case pin_scope(post) do
      {:group, group_id} ->
        # Pin/unpin is a moderate-tier action — moderators, admins, and
        # owners all qualify. `can_moderate?/2` also lets instance
        # staff through, matching the rest of the group permission
        # ladder.
        Hybridsocial.Groups.can_moderate?(group_id, actor_identity_id)

      {:page, page_id} ->
        # Use the moderate-tier predicate so the explicit moderator
        # role can pin without having broader edit authority. Editors
        # and admins still pass since `can_moderate?` is a superset.
        Hybridsocial.Pages.can_moderate?(page_id, actor_identity_id)

      {:profile, owner_id} ->
        owner_id == actor_identity_id
    end
  end

  # --- Hashtags ---

  def extract_hashtags(content) when is_binary(content) do
    # Unicode-aware so Arabic / Cyrillic / CJK / emoji-composed tags
    # round-trip through to the `hashtags` table. Kept in sync with
    # the inline linkifier in Content.MarkdownRenderer.link_hashtags/1.
    # Returns `{lowercase_name, original_display}` pairs so the upsert
    # can record the first author's casing without breaking lookup.
    ~r/#(\p{L}[\p{L}\p{M}\p{N}_]{0,100})/u
    |> Regex.scan(content)
    |> Enum.map(fn [_, tag] -> {String.downcase(tag), tag} end)
    |> Enum.uniq_by(fn {name, _} -> name end)
  end

  def extract_hashtags(_), do: []

  # --- Identity posts ---

  def posts_by_identity(identity_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_page_size)
    max_id = Keyword.get(opts, :max_id)
    exclude_replies = Keyword.get(opts, :exclude_replies, false)
    only_media = Keyword.get(opts, :only_media, false)
    only_direct = Keyword.get(opts, :only_direct, false)
    pinned = Keyword.get(opts, :pinned, false)
    viewer_id = Keyword.get(opts, :viewer_id)

    base =
      Post
      |> where([p], is_nil(p.deleted_at))
      # `id DESC` is the explicit tie-breaker for posts published in
      # the same instant; without it the row-tuple cursor below
      # couldn't pick a deterministic next-page boundary.
      |> order_by([p], desc: p.published_at, desc: p.id)
      |> limit(^limit)

    base =
      if Keyword.get(opts, :include_suspended, false),
        do: base,
        else: Hybridsocial.Feeds.Visibility.apply_suspension_filter(base)

    base = if pinned, do: where(base, [p], p.is_pinned == true), else: base

    # The "Direct" profile tab is a recipient-facing view: it shows
    # every direct-visibility post the identity is either the author
    # OR explicitly mentioned in. Other tabs (posts/replies/media)
    # stay author-scoped as before.
    query =
      if only_direct do
        mentioned_post_ids =
          from pm in Hybridsocial.Social.PostMention,
            where: pm.identity_id == ^identity_id,
            select: pm.post_id

        base
        |> where([p], p.visibility == "direct")
        |> where([p], p.identity_id == ^identity_id or p.id in subquery(mentioned_post_ids))
      else
        where(base, [p], p.identity_id == ^identity_id)
      end

    # Profile pagination orders by `published_at`, so a `p.id < max_id`
    # UUID compare against that ordering returns an arbitrary slice
    # and the profile freezes after one page (37 posts in the field
    # report). Look up the boundary post's published_at first, then
    # row-tuple compare on the same expression as the ORDER BY. Falls
    # through to no-cursor when the cursor doesn't resolve (stale
    # client, deleted post, etc.) — never emit an empty page just
    # because the cursor is unrecognised.
    query =
      case lookup_published_cursor(max_id) do
        nil ->
          query

        {pa, id} ->
          where(
            query,
            [p],
            fragment("(?, ?) < (?, ?)", p.published_at, p.id, ^pa, type(^id, Ecto.UUID))
          )
      end

    query = if exclude_replies, do: where(query, [p], is_nil(p.parent_id)), else: query
    query = if only_media, do: where(query, [p], p.post_type == "media"), else: query

    # Apply viewer-scoped block/mute/visibility filtering so a user's
    # profile feed respects the same audience contract as a per-post
    # detail fetch. The Direct tab hits a recipient-scoped path
    # already (only_direct=true above) so we skip the visibility
    # gate there — otherwise the gate would re-restrict it to "posts
    # whose audience includes the viewer", which is the same set
    # /Direct already returns.
    query =
      query
      |> Hybridsocial.Feeds.Visibility.apply_block_filter(viewer_id)
      |> Hybridsocial.Feeds.Visibility.apply_mute_filter(viewer_id)

    query =
      if only_direct do
        query
      else
        Hybridsocial.Feeds.Visibility.apply_post_visibility(query, viewer_id)
      end

    Repo.all(query) |> Repo.preload([:identity, :quote])
  end

  defp lookup_published_cursor(nil), do: nil

  defp lookup_published_cursor(id) when is_binary(id) do
    case Repo.one(from p in Post, where: p.id == ^id, select: {p.published_at, p.id}) do
      nil -> nil
      {nil, _id} -> nil
      {pa, pid} -> {pa, pid}
    end
  end

  defp lookup_published_cursor(_), do: nil

  # --- Admin operations ---

  @doc """
  Retrieves any post by ID, including private/deleted posts. For admin use only.
  """
  def admin_get_post(post_id) do
    Post
    |> Repo.get(post_id)
    |> case do
      nil -> {:error, :not_found}
      post -> {:ok, Repo.preload(post, [:identity, :parent, :quote, poll: :options])}
    end
  end

  @doc """
  Soft-deletes any post (sets deleted_at) with an audit log entry.
  Also publishes a Delete ActivityPub activity for federated posts.
  """
  def admin_delete_post(post_id, admin_id, reason \\ "") do
    with {:ok, post} <- admin_get_post(post_id),
         {:ok, post} <- do_admin_soft_delete(post) do
      Hybridsocial.Moderation.log(admin_id, "post.admin_deleted", "post", post_id, %{
        reason: reason,
        post_identity_id: post.identity_id
      })

      # A staff removal with a reason is a takedown: notify the author with the
      # reason and open the appeal window. (Owner-initiated delete_post/2 is a
      # separate path and never lands here.)
      maybe_open_post_takedown(post, admin_id, reason)

      # Publish Delete activity for federated posts
      if post.ap_id do
        try do
          activity = Hybridsocial.Federation.ActivityBuilder.build_delete(post)
          Hybridsocial.Federation.Publisher.publish(activity, post.identity)
        rescue
          _ -> :ok
        end
      end

      {:ok, post}
    end
  end

  defp maybe_open_post_takedown(post, moderator_id, reason) do
    if is_binary(reason) and reason != "" and post.identity_id do
      Hybridsocial.Moderation.create_takedown(%{
        target_type: "post",
        target_id: post.id,
        owner_id: post.identity_id,
        moderator_id: moderator_id,
        reason: reason
      })
    end

    :ok
  end

  defp do_admin_soft_delete(%Post{deleted_at: nil} = post) do
    post
    |> Post.soft_delete_changeset()
    |> Repo.update()
  end

  defp do_admin_soft_delete(%Post{} = post), do: {:ok, post}

  @doc """
  Reverses an admin soft-delete (used when a takedown appeal is approved).
  Clears `deleted_at` and audit-logs the restore. The caller is responsible for
  authorization (the appeal-approval path is already staff-gated).
  """
  def admin_restore_post(post_id, admin_id, reason \\ "") do
    case Repo.get(Post, post_id) do
      nil ->
        {:error, :not_found}

      %Post{deleted_at: nil} = post ->
        {:ok, post}

      post ->
        case post |> Post.restore_changeset() |> Repo.update() do
          {:ok, restored} ->
            Hybridsocial.Moderation.log(admin_id, "post.admin_restored", "post", post_id, %{
              reason: reason
            })

            {:ok, restored}

          error ->
            error
        end
    end
  end

  @doc """
  PERMANENTLY deletes a post. Used only by the takedown auto-purge worker after
  the appeal window. Reactions, boosts, mentions and stream-views cascade via
  `on_delete: :delete_all`; the post's media is `nilify_all`, so it is deleted
  explicitly here rather than left orphaned with a null `post_id`. Irreversible.
  """
  def purge_post(post_id) do
    case Repo.get(Post, post_id) do
      nil ->
        {:ok, :already_gone}

      post ->
        Ecto.Multi.new()
        |> Ecto.Multi.delete_all(
          :media,
          from(m in Hybridsocial.Media.MediaFile, where: m.post_id == ^post_id)
        )
        |> Ecto.Multi.delete(:post, post)
        |> Repo.transaction()
        |> case do
          {:ok, _} -> {:ok, :purged}
          {:error, _step, reason, _} -> {:error, reason}
        end
    end
  end

  @doc """
  Force-marks a post as sensitive with an audit log entry.
  """
  def admin_force_sensitive(post_id, admin_id) do
    with {:ok, post} <- admin_get_post(post_id) do
      case post
           |> Ecto.Changeset.change(sensitive: true)
           |> Repo.update() do
        {:ok, updated} ->
          Hybridsocial.Moderation.log(admin_id, "post.force_sensitive", "post", post_id, %{
            post_identity_id: post.identity_id
          })

          {:ok, updated}

        error ->
          error
      end
    end
  end

  @doc """
  Removes forced sensitive marking from a post with an audit log entry.
  """
  def admin_remove_sensitive(post_id, admin_id) do
    with {:ok, post} <- admin_get_post(post_id) do
      case post
           |> Ecto.Changeset.change(sensitive: false)
           |> Repo.update() do
        {:ok, updated} ->
          Hybridsocial.Moderation.log(admin_id, "post.remove_sensitive", "post", post_id, %{
            post_identity_id: post.identity_id
          })

          {:ok, updated}

        error ->
          error
      end
    end
  end

  @doc """
  Admin-hide: drop the post from public timelines without deleting
  it. Permalink still resolves; the post's own page, its author's
  profile (when viewed by the author or an admin), and existing
  replies stay accessible.
  """
  def admin_hide_post(post_id, admin_id) do
    with {:ok, post} <- admin_get_post(post_id) do
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      case post
           |> Ecto.Changeset.change(hidden_at: now, hidden_by: admin_id)
           |> Repo.update() do
        {:ok, updated} ->
          Hybridsocial.Moderation.log(admin_id, "post.hidden", "post", post_id, %{
            post_identity_id: post.identity_id
          })

          {:ok, updated}

        err ->
          err
      end
    end
  end

  @doc "Admin-unhide: restore the post to public timelines."
  def admin_unhide_post(post_id, admin_id) do
    with {:ok, post} <- admin_get_post(post_id) do
      case post
           |> Ecto.Changeset.change(hidden_at: nil, hidden_by: nil)
           |> Repo.update() do
        {:ok, updated} ->
          Hybridsocial.Moderation.log(admin_id, "post.unhidden", "post", post_id, %{
            post_identity_id: post.identity_id
          })

          {:ok, updated}

        err ->
          err
      end
    end
  end

  @doc """
  Admin-lock: reject further replies to this post and everything
  under it. `create_post/3` checks the target's `replies_locked_at`
  (and walks to root) before inserting.
  """
  def admin_lock_replies(post_id, admin_id) do
    with {:ok, post} <- admin_get_post(post_id) do
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      case post
           |> Ecto.Changeset.change(replies_locked_at: now, replies_locked_by: admin_id)
           |> Repo.update() do
        {:ok, updated} ->
          Hybridsocial.Moderation.log(admin_id, "post.replies_locked", "post", post_id, %{
            post_identity_id: post.identity_id
          })

          {:ok, updated}

        err ->
          err
      end
    end
  end

  @doc """
  Admin re-fetch: pull the AP object fresh from its origin and apply
  the current content/sensitivity/spoiler/language back to the local
  row. Only works on remote posts — locals have no upstream to refetch
  from. The content is re-stripped and the `content_html` is
  overwritten; counts (reply_count, boost_count, reaction_count) are
  left alone because they're local aggregates, not origin truth.
  """
  def admin_refetch_post(post_id, admin_id) do
    with {:ok, post} <- admin_get_post(post_id),
         true <- is_binary(post.ap_id) || {:error, :not_remote},
         :ok <- ensure_remote(post),
         {:ok, object} <- Hybridsocial.Federation.ObjectResolver.resolve(post.ap_id) do
      attrs = Hybridsocial.Federation.ActivityMapper.to_post(object)

      changeset =
        post
        |> Ecto.Changeset.cast(attrs, [
          :content,
          :content_html,
          :sensitive,
          :spoiler_text,
          :language
        ])

      case Repo.update(changeset) do
        {:ok, updated} ->
          Hybridsocial.Moderation.log(admin_id, "post.refetched", "post", post_id, %{
            ap_id: post.ap_id
          })

          {:ok, updated}

        err ->
          err
      end
    else
      {:error, :not_remote} -> {:error, :not_remote}
      false -> {:error, :not_remote}
      {:error, reason} -> {:error, reason}
    end
  end

  # A post is "remote" iff its ap_id lives on a different host than
  # the local endpoint. Local posts have ap_id under our own URL.
  defp ensure_remote(%Post{ap_id: ap_id}) when is_binary(ap_id) do
    local_host = URI.parse(HybridsocialWeb.Endpoint.url()).host

    case URI.parse(ap_id).host do
      ^local_host -> {:error, :not_remote}
      nil -> {:error, :not_remote}
      _ -> :ok
    end
  end

  defp ensure_remote(_), do: {:error, :not_remote}

  @doc "Admin-unlock replies."
  def admin_unlock_replies(post_id, admin_id) do
    with {:ok, post} <- admin_get_post(post_id) do
      case post
           |> Ecto.Changeset.change(replies_locked_at: nil, replies_locked_by: nil)
           |> Repo.update() do
        {:ok, updated} ->
          Hybridsocial.Moderation.log(admin_id, "post.replies_unlocked", "post", post_id, %{
            post_identity_id: post.identity_id
          })

          {:ok, updated}

        err ->
          err
      end
    end
  end

  # --- Private helpers ---

  defp get_owned_post(post_id, identity_id) do
    Post
    |> where([p], is_nil(p.deleted_at))
    |> Repo.get(post_id)
    |> case do
      nil ->
        {:error, :not_found}

      %Post{identity_id: ^identity_id} = post ->
        {:ok, post}

      # A post authored *as a page* is owned by the page identity, not the
      # human who wrote it — so a strict identity match always fails and the
      # post would be uneditable/undeletable. Mirror the create-time authority
      # (`Pages.resolve_post_author` → `can_edit?`): anyone who can edit the
      # page can edit and delete its posts.
      %Post{page_id: page_id} = post when is_binary(page_id) ->
        if Hybridsocial.Pages.can_edit?(page_id, identity_id) do
          {:ok, post}
        else
          {:error, :forbidden}
        end

      _post ->
        {:error, :forbidden}
    end
  end

  defp get_existing_post(post_id) do
    case get_post(post_id) do
      nil -> {:error, :not_found}
      post -> {:ok, post}
    end
  end

  defp get_existing_reaction(post_id, identity_id, nil) do
    Reaction
    |> where(
      [r],
      r.post_id == ^post_id and r.identity_id == ^identity_id and is_nil(r.target_media_id)
    )
    |> Repo.one()
  end

  defp get_existing_reaction(post_id, identity_id, target_media_id) do
    Reaction
    |> where(
      [r],
      r.post_id == ^post_id and r.identity_id == ^identity_id and
        r.target_media_id == ^target_media_id
    )
    |> Repo.one()
  end

  defp get_existing_boost(post_id, identity_id) do
    Boost
    |> where(
      [b],
      b.post_id == ^post_id and b.identity_id == ^identity_id and is_nil(b.deleted_at)
    )
    |> Repo.one()
  end

  @doc """
  Bump a parent post's `reply_count` when a reply is created. Shared by
  local reply creation and federation ingest (a remote reply to a post we
  host or mirror) so both paths keep the counter accurate — otherwise
  replies arriving over federation would never show up in the count,
  which is most visible on the global timeline.
  """
  def increment_reply_count(parent_id) do
    Post
    |> where([p], p.id == ^parent_id)
    |> Repo.update_all(inc: [reply_count: 1])
  end

  @doc """
  Drop a parent post's `reply_count` when a reply is deleted. Floors at 0
  so create/delete drift can't push the counter negative. Shared by local
  and federated delete paths.
  """
  def decrement_reply_count(parent_id) do
    Post
    |> where([p], p.id == ^parent_id and p.reply_count > 0)
    |> Repo.update_all(inc: [reply_count: -1])
  end

  defp update_reaction_count(post_id, delta) do
    Post
    |> where([p], p.id == ^post_id)
    |> Repo.update_all(inc: [reaction_count: delta])
  end

  defp update_boost_count(post_id, delta) do
    Post
    |> where([p], p.id == ^post_id)
    |> Repo.update_all(inc: [boost_count: delta])
  end

  defp get_next_revision_number(post_id) do
    PostRevision
    |> where([r], r.post_id == ^post_id)
    |> select([r], count(r.id))
    |> Repo.one()
    |> Kernel.+(1)
  end

  defp extract_and_link_hashtags(post) do
    link_hashtags(post, extract_hashtags(post.content))
  end

  @doc """
  Upsert and link a list of `{lowercase_name, display}` hashtag pairs to a
  post. Shared by local create (body extraction) and federation ingest
  (AP `tag` Hashtag entries + remote body, via Federation.Inbox). Idempotent
  per (post, hashtag); each distinct tag bumps the hashtag's `usage_count`
  once per post. This is the single seam that lets both local and remote
  posts feed the origin-agnostic trending query.
  """
  def link_hashtags(%Post{} = post, pairs) when is_list(pairs) do
    pairs
    |> Enum.uniq_by(fn {name, _display} -> name end)
    |> Enum.each(fn {name, display} ->
      {:ok, hashtag} = upsert_hashtag(name, display)
      link_post_hashtag(post.id, hashtag.id)
    end)
  end

  # First-writer-wins for display casing. The `set:` clause only
  # touches usage_count + updated_at; on conflict the existing
  # display_name is preserved, so once a tag has been recorded as
  # "#HelloWorld" by the first author, later "#helloworld" or
  # "#HELLOWORLD" still bumps the same row but doesn't overwrite
  # the canonical display.
  defp upsert_hashtag(name, display) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    %Hashtag{}
    |> Hashtag.changeset(%{name: name, display_name: display})
    |> Repo.insert(
      on_conflict: [inc: [usage_count: 1]],
      conflict_target: [:name],
      returning: true,
      set: [usage_count: dynamic([h], h.usage_count + 1), updated_at: now]
    )
  end

  defp link_post_hashtag(post_id, hashtag_id) do
    {:ok, post_uuid} = Ecto.UUID.dump(post_id)
    {:ok, hashtag_uuid} = Ecto.UUID.dump(hashtag_id)

    Repo.insert_all(
      "post_hashtags",
      [%{post_id: post_uuid, hashtag_id: hashtag_uuid}],
      on_conflict: :nothing,
      conflict_target: [:post_id, :hashtag_id]
    )
  end
end
