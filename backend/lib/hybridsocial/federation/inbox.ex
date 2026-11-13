defmodule Hybridsocial.Federation.Inbox do
  @moduledoc """
  Main inbox processor for incoming ActivityPub activities.
  Dispatches to the appropriate handler based on activity type.
  """

  import Ecto.Query

  alias Hybridsocial.Repo
  alias Hybridsocial.Accounts
  alias Hybridsocial.Accounts.Identity
  alias Hybridsocial.Media.MediaFile
  alias Hybridsocial.Social
  alias Hybridsocial.Social.Post
  alias Hybridsocial.Social.Posts
  alias Hybridsocial.Federation.ActivityMapper
  alias Hybridsocial.Federation.ObjectResolver
  alias Hybridsocial.Federation.Containment
  alias Hybridsocial.Federation.Validator, as: ActivityValidator
  alias Hybridsocial.Federation.MRF

  require Logger

  @doc """
  Processes an incoming ActivityPub activity.

  Before dispatching to type-specific handlers, runs:
  1. Containment checks (origin verification)
  2. Activity validation
  3. MRF policy pipeline
  """
  def process(%{"type" => type} = activity) do
    Logger.info("Processing #{type} activity: #{activity["id"]}")

    with :ok <- run_containment(activity),
         {:ok, activity} <- run_validation(activity),
         {:ok, activity} <- run_mrf(activity) do
      # Some handlers legitimately have no result to return and hand back
      # bare `:ok` (e.g. a poll-vote Update that just refreshes cached
      # tallies). Normalise to the `{:ok, _}` contract the inbox
      # controller's `with` expects, so a valid activity can never crash
      # the pipeline with a WithClauseError.
      case dispatch(type, activity) do
        :ok -> {:ok, :accepted}
        other -> other
      end
    end
  end

  def process(_), do: {:error, :invalid_activity}

  # --- Pre-processing pipeline ---

  defp run_containment(activity) do
    actor = Containment.get_actor(activity)
    activity_id = activity["id"]

    cond do
      is_nil(actor) ->
        {:error, :missing_actor}

      is_binary(activity_id) and Containment.contain_origin(activity_id, activity) == :error ->
        Logger.warning("Containment: origin mismatch for #{activity_id}")
        {:error, :containment_origin_mismatch}

      Containment.contain_child(activity) == :error ->
        Logger.warning("Containment: child origin mismatch for #{activity_id}")
        {:error, :containment_child_mismatch}

      true ->
        :ok
    end
  end

  defp run_validation(activity) do
    case ActivityValidator.validate(activity) do
      {:ok, activity} ->
        {:ok, activity}

      {:error, reason} ->
        Logger.warning("Validation failed for #{activity["id"]}: #{inspect(reason)}")
        {:error, {:validation_failed, reason}}
    end
  end

  defp run_mrf(activity) do
    case MRF.filter_pipeline(activity) do
      {:ok, activity} ->
        {:ok, activity}

      {:reject, reason} ->
        Logger.info("MRF rejected #{activity["id"]}: #{reason}")
        {:error, {:mrf_rejected, reason}}
    end
  end

  defp dispatch("Follow", activity), do: handle_follow(activity)
  defp dispatch("Accept", activity), do: handle_accept(activity)
  defp dispatch("Reject", activity), do: handle_reject(activity)
  defp dispatch("Create", activity), do: handle_create(activity)
  defp dispatch("Like", activity), do: handle_like(activity)
  defp dispatch("EmojiReact", activity), do: handle_emoji_react(activity)
  defp dispatch("Announce", activity), do: handle_announce(activity)
  defp dispatch("Delete", activity), do: handle_delete(activity)
  defp dispatch("Update", activity), do: handle_update(activity)
  defp dispatch("Block", activity), do: handle_block(activity)
  defp dispatch("Undo", activity), do: handle_undo(activity)
  defp dispatch("Move", activity), do: handle_move(activity)
  defp dispatch("Flag", activity), do: handle_flag(activity)
  defp dispatch("Add", activity), do: handle_add(activity)
  defp dispatch("Remove", activity), do: handle_remove(activity)
  defp dispatch(_, _activity), do: {:error, :unsupported_activity_type}

  # --- Follow ---
  # A remote actor wants to follow a local actor.

  defp handle_follow(%{"actor" => actor_ap_id, "object" => object_ap_id} = activity)
       when is_binary(actor_ap_id) and is_binary(object_ap_id) do
    with {:ok, local_identity} <- resolve_local_identity(object_ap_id),
         {:ok, remote_identity} <- resolve_or_create_remote_identity(actor_ap_id) do
      status = if local_identity.is_locked, do: :pending, else: :accepted

      result =
        Social.follow(remote_identity.id, local_identity.id)

      case result do
        {:ok, follow} ->
          if status == :accepted do
            # Send Accept back to the remote side so they flip the
            # FollowRequest into a confirmed Follow on their end.
            # Without this, the peer's side sits in pending forever
            # and our accept is invisible to them.
            publish_follow_accept(local_identity, remote_identity, activity)
            Logger.info("Auto-accepted follow from #{actor_ap_id}")
          end

          # Bell the followed user. follow_request vs follow differ
          # in type so the UI can render "accept / decline" buttons
          # for locked accounts.
          notification_type =
            if status == :pending, do: "follow_request", else: "follow"

          Hybridsocial.Notifications.create_notification(%{
            recipient_id: local_identity.id,
            actor_id: remote_identity.id,
            type: notification_type
          })

          {:ok, %{follow: follow, activity: activity}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp handle_follow(_), do: {:error, :invalid_follow_activity}

  # Builds an Accept{Follow} activity wrapping the original Follow
  # and posts it to the remote actor's inbox over a signed HTTP
  # request. Best-effort — failures log but don't block the local
  # follow record (we can retry via the publisher's failed-delivery
  # backoff).
  defp publish_follow_accept(local_identity, remote_identity, follow_activity) do
    # Mastodon wants the Accept's `object` to be either the Follow's
    # `id` URI OR the embedded Follow activity. ActivityBuilder takes
    # the URI; replace `object` with the full embedded Follow for max
    # compatibility (Mastodon accepts both, Pleroma prefers embedded).
    follow_id = follow_activity["id"]

    accept =
      Hybridsocial.Federation.ActivityBuilder.build_accept_follow(
        local_identity,
        follow_id
      )
      |> Map.put("object", follow_activity)

    inbox_url = remote_identity.inbox_url || derive_inbox_url(remote_identity)

    if is_binary(inbox_url) and inbox_url != "" do
      Hybridsocial.Federation.deliver_async(fn ->
        case Hybridsocial.Federation.Publisher.deliver(accept, inbox_url, local_identity) do
          {:ok, _} ->
            Logger.info("Accept{Follow} delivered to #{inbox_url}")

          {:error, reason} ->
            Logger.warning("Accept{Follow} delivery failed to #{inbox_url}: #{inspect(reason)}")
        end
      end)
    else
      Logger.warning("No inbox URL for #{remote_identity.ap_actor_url} — Accept not delivered")
    end
  end

  defp derive_inbox_url(%Identity{ap_actor_url: ap_url}) when is_binary(ap_url) do
    ap_url <> "/inbox"
  end

  defp derive_inbox_url(_), do: nil

  # --- Accept ---
  # A remote actor accepted our follow request.

  defp handle_accept(%{"actor" => actor_ap_id, "object" => object})
       when is_binary(actor_ap_id) do
    # Check the raw object (before normalization, which strips
    # `type` + `object`) so we can tell a relay-shaped Follow from
    # a user-follow Accept:
    #
    #   * Mastodon-style: object == AS:Public
    #   * Pleroma-style : object == the relay's own actor URL
    #
    # accept_relay/1 handles both by looking up actor_url or by
    # host-matching the inbox URL.
    if relay_follow?(object) do
      Hybridsocial.Federation.Relays.accept_relay(actor_ap_id)
    else
      follow_object = normalize_object(object)

      with {:ok, remote_identity} <- resolve_remote_identity(actor_ap_id),
           {:ok, follow} <- find_pending_follow(follow_object, remote_identity.id) do
        Social.accept_follow(follow.id)
      end
    end
  end

  defp handle_accept(_), do: {:error, :invalid_accept_activity}

  # A Follow with object = AS:Public is always a relay Follow. A
  # Follow whose object is a remote actor might be either a user
  # follow or a Pleroma-style relay follow; accept_relay/1 will
  # return :not_found if no matching row exists, which lets the
  # caller fall through to user-follow handling.
  defp relay_follow?(%{
         "type" => "Follow",
         "object" => "https://www.w3.org/ns/activitystreams#Public"
       }),
       do: true

  defp relay_follow?(%{"type" => "Follow", "object" => object})
       when is_binary(object),
       do: known_relay_actor?(object)

  defp relay_follow?(_), do: false

  defp known_relay_actor?(actor_url) do
    import Ecto.Query

    Hybridsocial.Repo.exists?(
      from r in Hybridsocial.Federation.Relay, where: r.actor_url == ^actor_url
    )
  end

  # --- Reject ---
  # A remote actor rejected our follow request.

  defp handle_reject(%{"actor" => actor_ap_id, "object" => object})
       when is_binary(actor_ap_id) do
    follow_object = normalize_object(object)

    with {:ok, remote_identity} <- resolve_remote_identity(actor_ap_id),
         {:ok, follow} <- find_pending_follow(follow_object, remote_identity.id) do
      Social.reject_follow(follow.id)
    end
  end

  defp handle_reject(_), do: {:error, :invalid_reject_activity}

  # --- Create ---
  # A remote actor created a new object (Note, Article, Question, Audio, Video, Page, etc.).

  defp handle_create(%{"actor" => actor_ap_id, "object" => %{"type" => "Answer"} = object})
       when is_binary(actor_ap_id) do
    # Answer objects are poll responses — delegate to poll handling
    handle_poll_answer(actor_ap_id, object)
  end

  # Only Pleroma/Akkoma's native ChatMessage type routes to the DM
  # inbox. Everything else — including Mastodon's `visibility: direct`
  # statuses that carry `directMessage: true` — is a Note and flows
  # into `handle_create_post`, where `ActivityMapper.to_post` preserves
  # the "direct" visibility. Mastodon-class servers can't thread real
  # DMs anyway (each reply arrives as a standalone status), so we
  # respect the sender's intent: ChatMessage means chat, Note means
  # post, no exceptions.
  defp handle_create(%{"actor" => actor_ap_id, "object" => %{"type" => "ChatMessage"} = object})
       when is_binary(actor_ap_id) do
    handle_direct_message(actor_ap_id, object)
  end

  defp handle_create(%{"actor" => actor_ap_id, "object" => object})
       when is_binary(actor_ap_id) and is_map(object) do
    handle_create_post(actor_ap_id, object)
  end

  defp handle_create(%{"actor" => actor_ap_id, "object" => object_id})
       when is_binary(actor_ap_id) and is_binary(object_id) do
    # Object is just an ID reference -- we'd need to fetch it.
    # For now, return an error since we can't process inline.
    {:error, :object_must_be_embedded}
  end

  defp handle_create(_), do: {:error, :invalid_create_activity}

  defp handle_create_post(actor_ap_id, object) do
    with {:ok, remote_identity} <- resolve_or_create_remote_identity(actor_ap_id) do
      post_attrs = ActivityMapper.to_post(object)

      # Run content filters with "remote" scope for federated content
      content_text = post_attrs["content"] || ""

      case Hybridsocial.Moderation.check_content(content_text, "remote") do
        {:reject, reason} ->
          Logger.info("Rejected remote post from #{actor_ap_id}: #{reason}")
          {:error, :content_rejected}

        {:flag, reason} ->
          # Allow the post but queue it for moderation review
          result = insert_remote_post(post_attrs, remote_identity, object)

          case result do
            {:ok, post} ->
              Hybridsocial.Moderation.queue_for_review(%{
                "item_type" => "post",
                "item_id" => post.id,
                "source" => "content_filter",
                "reason" => reason,
                "severity" => "medium"
              })

              {:ok, post}

            error ->
              error
          end

        _ ->
          insert_remote_post(post_attrs, remote_identity, object)
      end
    end
  end

  defp insert_remote_post(post_attrs, remote_identity, ap_object) do
    case get_post_by_ap_id(post_attrs["ap_id"]) do
      nil ->
        parent_ap_id = post_attrs["parent_ap_id"]
        parent_id = resolve_parent_post_id(parent_ap_id)

        insert_attrs =
          post_attrs
          |> Map.delete("parent_ap_id")
          |> Map.put("identity_id", remote_identity.id)
          |> Map.put("parent_ap_id", parent_ap_id)
          |> maybe_put_parent(parent_id)
          |> Posts.maybe_resolve_root_id()

        result =
          %Post{}
          |> Post.create_changeset(insert_attrs, has_media: remote_media?(ap_object))
          |> maybe_put_published_at(post_attrs["published_at"])
          |> maybe_put_content_html(post_attrs["content_html"])
          |> Repo.insert()

        # Persist any attachments alongside the post — these become
        # MediaFile rows with remote_url set, which the serializer
        # rewrites through the media proxy at render time.
        case result do
          {:ok, post} ->
            persist_remote_attachments(post, ap_object, remote_identity)
            persist_remote_mentions(post, ap_object)
            persist_remote_hashtags(post, ap_object)
            persist_remote_poll(post, post_attrs)
            Posts.broadcast_direct_post_to_participants(post)
            notify_remote_reply(post, parent_id)
            notify_remote_quote(post, ap_object)

            # Live-feed streaming: push new TOP-LEVEL remote posts to the same
            # streams local posts use (Posts.create_post) so the Global feed
            # shows them in real time and ticks its "N new posts" banner, and a
            # local user following a remote account gets a live home update.
            # Without this, only LOCAL posts ever reached `timeline:public`, so
            # the (federated) Global feed never updated. Replies are skipped —
            # they don't belong in the public/global timeline (which filters on
            # parent_ap_id) and the client drops them anyway. Backfilled thread
            # ancestors never reach this path, so old posts don't masquerade as
            # new.
            if is_nil(parent_ap_id), do: stream_remote_post(post)

            # Thread-bump the ancestors if we linked a local parent —
            # same semantics as local reply creation in Posts.create_post.
            # Without this, a reply from federation wouldn't surface the
            # local thread back to the top of Explore. The reply_count
            # bump mirrors local reply creation too: without it, federated
            # replies never registered in the count (visible as "0
            # comments" on posts in the global feed).
            if parent_id do
              Posts.increment_reply_count(parent_id)
              Posts.bump_thread_activity_public(post)
            end

          _ ->
            :ok
        end

        # If parent couldn't be resolved locally, try backfilling from remote
        case {result, parent_ap_id, parent_id} do
          {{:ok, post}, ap_id, nil} when is_binary(ap_id) ->
            schedule_thread_backfill(post.id, ap_id)
            {:ok, post}

          _ ->
            result
        end

      existing ->
        {:ok, existing}
    end
  end

  # AP attachments arrive as a list of objects under `attachment`.
  # Mastodon/Pleroma/Akkoma all use `Document` for images; some
  # implementations use `Image`/`Audio`/`Video` directly. We accept
  # any with a `url` + `mediaType`. Bytes are NOT downloaded here —
  # the proxy fetches lazily on first user request.
  # Scan the note's `tag` array for Mentions and link them to local
  # identities. For direct-visibility posts this is what unlocks access:
  # a post with `visibility: direct` is viewable by the author plus
  # anyone in `post_mentions`.
  defp persist_remote_mentions(%Post{id: post_id, identity_id: author_id} = post, %{"tag" => tags})
       when is_list(tags) do
    mentioned_ids =
      for tag <- tags,
          is_map(tag),
          tag["type"] == "Mention",
          href = tag["href"],
          is_binary(href),
          identity = lookup_local_identity_for_mention(href),
          not is_nil(identity) do
        %Hybridsocial.Social.PostMention{}
        |> Hybridsocial.Social.PostMention.changeset(%{
          post_id: post_id,
          identity_id: identity.id
        })
        |> Repo.insert(on_conflict: :nothing)

        identity.id
      end

    Hybridsocial.Notifications.notify_mention(author_id, post, Enum.uniq(mentioned_ids))

    :ok
  end

  defp persist_remote_mentions(_post, _object), do: :ok

  # Extract hashtags for a remote post and link them into `post_hashtags`.
  # Sources, deduped by Posts.link_hashtags/2:
  #   1. the AP `tag` array — authoritative `type: "Hashtag"` entries the
  #      origin instance declared (Mastodon/Pleroma/etc.);
  #   2. the post body — fallback for peers that only inline `#tags`.
  # This is what makes federated posts eligible for trending: the trending
  # query is origin-agnostic and simply joins `post_hashtags`, so without
  # this linking remote content could never trend, and remote hashtags
  # never accrued a usage_count. Local posts already do this in insert_post.
  defp persist_remote_hashtags(%Post{} = post, ap_object) do
    ap_tags = ActivityMapper.extract_hashtags(ap_object["tag"])
    body_tags = Posts.extract_hashtags(post.content)
    Posts.link_hashtags(post, ap_tags ++ body_tags)
    :ok
  end

  # Serialize a freshly-ingested remote post and push it to the live streams
  # exactly as Posts.create_post does for local posts (public timeline +
  # follower home fan-out + hashtag topics). Best-effort: a serialization
  # hiccup on an odd remote object must never fail the ingestion.
  defp stream_remote_post(%Post{} = post) do
    # The post is fresh from Repo.insert with no associations loaded; the
    # serializer needs the same preloads Posts.create_post uses. Attachments
    # and poll were persisted just above, so they're in the DB now.
    post = Repo.preload(post, [:media_attachments, :identity, poll: :options])
    serialized = HybridsocialWeb.Serializers.PostSerializer.serialize(post, [])
    Hybridsocial.Streaming.broadcast_post(serialized)
  rescue
    e -> Logger.warning("Failed to stream remote post #{post.id}: #{inspect(e)}")
  end

  # Persist a remote poll's options + cached vote counts so the
  # serializer can render `oneOf`/`anyOf` Question objects the same
  # way as locally-created polls. Without this, a `post_type=poll`
  # row exists with no `polls` row backing it and the post-detail
  # page renders blank.
  defp persist_remote_poll(%Post{id: post_id} = _post, %{"post_type" => "poll"} = post_attrs) do
    options = post_attrs["poll_options"] || []
    multiple = post_attrs["poll_multiple"] || false
    expires_at = post_attrs["poll_expires_at"]
    voters_count = post_attrs["poll_voters_count"] || 0

    # Skip if we somehow ingested a Question with no choices — the
    # post itself stands; the poll just won't render. Better than
    # crashing the inbox on a malformed peer object.
    if options == [] do
      :ok
    else
      multi =
        Ecto.Multi.new()
        |> Ecto.Multi.insert(:poll, fn _ ->
          %Hybridsocial.Social.Poll{}
          |> Hybridsocial.Social.Poll.changeset(%{
            post_id: post_id,
            multiple_choice: multiple,
            expires_at: parse_poll_expires_at(expires_at),
            voters_count: voters_count
          })
        end)
        |> Ecto.Multi.run(:options, fn _repo, %{poll: poll} ->
          insert_remote_poll_options(poll.id, options)
        end)

      case Repo.transaction(multi) do
        {:ok, _} ->
          :ok

        {:error, _step, reason, _} ->
          Logger.warning("Failed to persist remote poll for #{post_id}: #{inspect(reason)}")
          :ok
      end
    end
  end

  defp persist_remote_poll(_post, _attrs), do: :ok

  @doc """
  One-shot helper: refetches the AP Question for a remote `post_type=poll`
  row that's missing its poll row (pre-fix data) and persists the poll
  + options. Safe to call multiple times — bails when a poll already
  exists. Used via `mix run` / IEx eval after deploy to backfill.
  """
  def backfill_remote_poll(post_id) when is_binary(post_id) do
    case Repo.get(Post, post_id) do
      nil ->
        {:error, :not_found}

      post ->
        cond do
          post.post_type != "poll" ->
            {:error, :not_a_poll}

          not is_binary(post.ap_id) or post.ap_id == "" ->
            {:error, :not_remote}

          Repo.exists?(Ecto.Query.where(Hybridsocial.Social.Poll, [p], p.post_id == ^post.id)) ->
            {:ok, :already_persisted}

          true ->
            with {:ok, ap_object} <- fetch_ap_object(post.ap_id) do
              attrs = ActivityMapper.to_post(ap_object)
              persist_remote_poll(post, attrs)
              {:ok, :backfilled}
            end
        end
    end
  end

  defp fetch_ap_object(ap_id) do
    case Hybridsocial.Federation.SignedFetch.get(ap_id,
           follow_redirect: true,
           recv_timeout: 10_000
         ) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, ap} -> {:ok, ap}
          err -> err
        end

      {:ok, %{status_code: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp insert_remote_poll_options(poll_id, options) do
    results =
      options
      |> Enum.with_index()
      |> Enum.map(fn {opt, index} ->
        attrs = %{
          poll_id: poll_id,
          text: opt["name"],
          position: index
        }

        %Hybridsocial.Social.PollOption{}
        |> Hybridsocial.Social.PollOption.changeset(attrs)
        |> Repo.insert()
        |> case do
          {:ok, inserted} ->
            # Mirror the remote vote count the peer reported. Voting
            # state is read-only here; the source of truth stays on
            # the origin instance and we refresh on each Update.
            count = opt["votes_count"] || 0

            if count > 0 do
              Hybridsocial.Social.PollOption
              |> Ecto.Query.where([o], o.id == ^inserted.id)
              |> Repo.update_all(set: [votes_count: count])
            end

            {:ok, inserted}

          err ->
            err
        end
      end)

    case Enum.find(results, fn {status, _} -> status == :error end) do
      nil -> {:ok, Enum.map(results, fn {:ok, opt} -> opt end)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_poll_expires_at(nil), do: nil

  defp parse_poll_expires_at(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> DateTime.truncate(dt, :microsecond)
      _ -> nil
    end
  end

  defp parse_poll_expires_at(%DateTime{} = dt), do: DateTime.truncate(dt, :microsecond)
  defp parse_poll_expires_at(_), do: nil

  defp notify_remote_reply(_post, nil), do: :ok

  defp notify_remote_reply(%Post{} = post, parent_id) when is_binary(parent_id) do
    # Only fire when the parent is a local post — the federated
    # reply only needs a bell for OUR users. Remote-to-remote replies
    # flowing through our relay would otherwise spam our identities
    # that aren't involved.
    case Repo.get(Post, parent_id) do
      %Post{} = parent ->
        if Hybridsocial.Federation.LocalUrl.local_actor_url?(
             parent_author_ap_url(parent.identity_id)
           ) do
          Hybridsocial.Notifications.notify_reply(post.identity_id, post, parent)
        end

      _ ->
        :ok
    end
  end

  defp notify_remote_quote(%Post{} = post, %{"quoteUrl" => quote_url})
       when is_binary(quote_url) do
    case get_post_by_ap_id(quote_url) do
      %Post{identity_id: quoted_author_id} ->
        Hybridsocial.Notifications.create_notification(%{
          recipient_id: quoted_author_id,
          actor_id: post.identity_id,
          type: "quote",
          target_type: "post",
          target_id: post.id
        })

      _ ->
        :ok
    end
  end

  defp notify_remote_quote(_, _), do: :ok

  defp parent_author_ap_url(identity_id) do
    case Repo.get(Identity, identity_id) do
      %Identity{ap_actor_url: url} -> url
      _ -> nil
    end
  end

  # Mentions use `href` pointing at the mentioned actor. For a local
  # recipient this is our own `/actors/:id`; for remote actors it's
  # their AP URL. We only care about local matches here — remote
  # mentions don't grant access to a local post.
  defp lookup_local_identity_for_mention(href) do
    lookup_local_identity(href)
  end

  # Whether the object carries media we'll store: the same test
  # `persist_remote_attachments/3` applies, so a post accepted on the
  # strength of its media always gets that media. Lets an image-only Note
  # (no text, common from Pleroma/Misskey) through the content check, the
  # same rule a local post with media follows.
  defp remote_media?(ap_object) do
    ap_object["attachment"]
    |> List.wrap()
    |> Enum.any?(&match?(%{"url" => url} when is_binary(url), &1))
  end

  defp persist_remote_attachments(post, ap_object, remote_identity) do
    attachments = List.wrap(ap_object["attachment"])

    Enum.each(attachments, fn attachment ->
      with %{"url" => url} when is_binary(url) <- attachment,
           domain when is_binary(domain) <- ActivityMapper.extract_domain(url) do
        # Peers that omit mediaType leave us with octet-stream → "unknown"
        # type → a broken tile. Infer from the URL extension instead.
        media_type = ActivityMapper.resolve_remote_content_type(attachment["mediaType"], url)
        focal_point = attachment["focalPoint"] || []

        attrs = %{
          identity_id: remote_identity.id,
          post_id: post.id,
          content_type: media_type,
          remote_url: url,
          remote_origin_domain: domain,
          alt_text: attachment["name"],
          width: attachment["width"],
          height: attachment["height"],
          duration: attachment["duration"],
          blurhash: attachment["blurhash"],
          metadata: %{
            "ap_type" => attachment["type"],
            "focal_point" => focal_point
          }
        }

        case %MediaFile{}
             |> MediaFile.remote_changeset(attrs)
             |> Repo.insert() do
          {:ok, _} ->
            :ok

          {:error, changeset} ->
            Logger.warning(
              "[inbox] failed to persist remote attachment url=#{url} post=#{post.id} errors=#{inspect(changeset.errors)}"
            )
        end
      end
    end)
  end

  # --- Poll Answer ---
  # A remote actor submitted a poll answer.

  defp handle_poll_answer(actor_ap_id, %{"inReplyTo" => poll_ap_id, "name" => answer_name})
       when is_binary(poll_ap_id) and is_binary(answer_name) do
    with {:ok, remote_identity} <- resolve_or_create_remote_identity(actor_ap_id),
         {:ok, post} <- resolve_local_post(poll_ap_id) do
      # Look up the poll and find the option matching the answer name
      poll = Repo.one(from(p in Hybridsocial.Social.Poll, where: p.post_id == ^post.id))

      if poll do
        option =
          Repo.one(
            from(o in Hybridsocial.Social.PollOption,
              where: o.poll_id == ^poll.id and o.title == ^answer_name
            )
          )

        if option do
          Hybridsocial.Social.Polls.vote(poll.id, remote_identity.id, [option.id])
        else
          {:error, :poll_option_not_found}
        end
      else
        {:error, :poll_not_found}
      end
    end
  end

  defp handle_poll_answer(_actor_ap_id, _object), do: {:error, :invalid_poll_answer}

  # --- Like ---

  defp handle_like(%{"actor" => actor_ap_id, "object" => object_ap_id})
       when is_binary(actor_ap_id) and is_binary(object_ap_id) do
    with {:ok, remote_identity} <- resolve_or_create_remote_identity(actor_ap_id),
         {:ok, post} <- resolve_local_post(object_ap_id) do
      Hybridsocial.Social.Posts.react(post.id, remote_identity.id, "like")
    end
  end

  defp handle_like(_), do: {:error, :invalid_like_activity}

  # --- EmojiReact ---

  defp handle_emoji_react(%{
         "actor" => actor_ap_id,
         "object" => object_ap_id,
         "content" => content
       })
       when is_binary(actor_ap_id) and is_binary(object_ap_id) do
    reaction_type = ActivityMapper.to_reaction_type(content)

    with {:ok, remote_identity} <- resolve_or_create_remote_identity(actor_ap_id),
         {:ok, post} <- resolve_local_post(object_ap_id) do
      Hybridsocial.Social.Posts.react(post.id, remote_identity.id, reaction_type)
    end
  end

  defp handle_emoji_react(_), do: {:error, :invalid_emoji_react_activity}

  # --- Announce (Boost) ---

  defp handle_announce(%{"actor" => actor_ap_id, "object" => object_ap_id})
       when is_binary(actor_ap_id) and is_binary(object_ap_id) do
    with {:ok, remote_identity} <- resolve_or_create_remote_identity(actor_ap_id),
         {:ok, post} <- resolve_local_post(object_ap_id) do
      Hybridsocial.Social.Posts.boost(post.id, remote_identity.id)
    end
  end

  defp handle_announce(_), do: {:error, :invalid_announce_activity}

  # --- Delete ---

  defp handle_delete(%{"actor" => actor_ap_id, "object" => object})
       when is_binary(actor_ap_id) do
    object_ap_id = normalize_object_id(object)

    # An actor deleting *itself* — the account-deletion broadcast every
    # server sends when a user closes their account. It used to fall
    # through to the post lookup below, find nothing, and report
    # "already deleted", leaving the follow row in place so we kept
    # fanning out to a mailbox that no longer exists.
    if object_ap_id == actor_ap_id do
      Hybridsocial.Federation.DeadActors.handle_self_delete(actor_ap_id)
    else
      delete_post_activity(actor_ap_id, object_ap_id)
    end
  end

  defp handle_delete(_), do: {:error, :invalid_delete_activity}

  defp delete_post_activity(actor_ap_id, object_ap_id) do
    with {:ok, remote_identity} <- resolve_remote_identity(actor_ap_id) do
      case get_post_by_ap_id(object_ap_id) do
        %Post{identity_id: identity_id} = post when identity_id == remote_identity.id ->
          result =
            post
            |> Post.soft_delete_changeset()
            |> Repo.update()

          # Mirror local delete_post: drop the parent's reply_count so the
          # count stays accurate after a federated reply is retracted.
          with {:ok, %Post{parent_id: parent_id}} when not is_nil(parent_id) <- result do
            Posts.decrement_reply_count(parent_id)
          end

          result

        %Post{} ->
          {:error, :forbidden}

        nil ->
          # Post not found; may have already been deleted
          {:ok, :already_deleted}
      end
    end
  end

  # --- Update ---

  defp handle_update(%{"actor" => actor_ap_id, "object" => object})
       when is_binary(actor_ap_id) and is_map(object) do
    with {:ok, remote_identity} <- resolve_remote_identity(actor_ap_id) do
      case object["type"] do
        type when type in ["Person", "Service", "Organization", "Application", "Group"] ->
          # Update the remote actor's cached info
          actor_attrs = ActivityMapper.to_actor(object)

          remote_identity
          |> Identity.update_changeset(%{
            display_name: actor_attrs[:display_name],
            avatar_url: actor_attrs[:avatar_url]
          })
          |> Repo.update()

        type when type in ["Note", "Article"] ->
          update_remote_post(object, remote_identity)

        "Question" ->
          # Mastodon broadcasts an Update on every vote — used to
          # refresh `replies.totalItems` and `votersCount` on
          # subscribed peers. We mirror the new counts onto our
          # cached poll/option rows so remote-poll viewers see
          # live tallies.
          update_remote_poll(object, remote_identity)

        _ ->
          {:error, :unsupported_object_type}
      end
    end
  end

  defp handle_update(_), do: {:error, :invalid_update_activity}

  defp update_remote_poll(%{"id" => ap_id} = object, _remote_identity) when is_binary(ap_id) do
    case get_post_by_ap_id(ap_id) do
      nil ->
        {:error, :not_found}

      post ->
        case Repo.preload(post, poll: :options).poll do
          nil ->
            # The Question wasn't ingested as a poll for some reason
            # — treat the Update as the create signal and persist it.
            attrs = ActivityMapper.to_post(object)
            persist_remote_poll(post, attrs)

          poll ->
            options = object["oneOf"] || object["anyOf"] || []
            voters_count = (object["votersCount"] || poll.voters_count) |> max(0)

            # Match each incoming option by name (Mastodon convention)
            # and update the cached vote count. Names are unique per
            # poll on creation, so duplicates aren't a concern.
            for opt <- options do
              name = opt["name"]

              count =
                case opt do
                  %{"replies" => %{"totalItems" => n}} when is_integer(n) -> n
                  _ -> 0
                end

              if is_binary(name) do
                Hybridsocial.Social.PollOption
                |> Ecto.Query.where([o], o.poll_id == ^poll.id and o.text == ^name)
                |> Repo.update_all(set: [votes_count: count])
              end
            end

            Hybridsocial.Social.Poll
            |> Ecto.Query.where([p], p.id == ^poll.id)
            |> Repo.update_all(set: [voters_count: voters_count])

            {:ok, :poll_updated}
        end
    end
  end

  defp update_remote_poll(_, _), do: {:error, :invalid_question_object}

  # --- Block ---

  defp handle_block(%{"actor" => actor_ap_id, "object" => object_ap_id})
       when is_binary(actor_ap_id) and is_binary(object_ap_id) do
    with {:ok, remote_identity} <- resolve_or_create_remote_identity(actor_ap_id),
         {:ok, local_identity} <- resolve_local_identity(object_ap_id) do
      Social.block(remote_identity.id, local_identity.id)
    end
  end

  defp handle_block(_), do: {:error, :invalid_block_activity}

  # --- Undo ---

  defp handle_undo(%{"actor" => actor_ap_id, "object" => %{"type" => inner_type} = inner_object})
       when is_binary(actor_ap_id) do
    case inner_type do
      "Follow" -> undo_follow(actor_ap_id, inner_object)
      "Like" -> undo_like(actor_ap_id, inner_object)
      "Announce" -> undo_announce(actor_ap_id, inner_object)
      "Block" -> undo_block(actor_ap_id, inner_object)
      _ -> {:error, :unsupported_undo_type}
    end
  end

  defp handle_undo(_), do: {:error, :invalid_undo_activity}

  # --- Undo sub-handlers ---

  defp undo_follow(actor_ap_id, %{"object" => target_ap_id})
       when is_binary(target_ap_id) do
    with {:ok, remote_identity} <- resolve_remote_identity(actor_ap_id),
         {:ok, local_identity} <- resolve_local_identity(target_ap_id) do
      Social.unfollow(remote_identity.id, local_identity.id)
      {:ok, :unfollowed}
    end
  end

  defp undo_follow(_, _), do: {:error, :invalid_undo_follow}

  defp undo_like(actor_ap_id, %{"object" => object_ap_id})
       when is_binary(object_ap_id) do
    with {:ok, remote_identity} <- resolve_remote_identity(actor_ap_id),
         {:ok, post} <- resolve_local_post(object_ap_id) do
      Hybridsocial.Social.Posts.unreact(post.id, remote_identity.id)
    end
  end

  defp undo_like(_, _), do: {:error, :invalid_undo_like}

  defp undo_announce(actor_ap_id, %{"object" => object_ap_id})
       when is_binary(object_ap_id) do
    with {:ok, remote_identity} <- resolve_remote_identity(actor_ap_id),
         {:ok, post} <- resolve_local_post(object_ap_id) do
      Hybridsocial.Social.Posts.unboost(post.id, remote_identity.id)
    end
  end

  defp undo_announce(_, _), do: {:error, :invalid_undo_announce}

  defp undo_block(actor_ap_id, %{"object" => target_ap_id})
       when is_binary(target_ap_id) do
    with {:ok, remote_identity} <- resolve_remote_identity(actor_ap_id),
         {:ok, local_identity} <- resolve_local_identity(target_ap_id) do
      Social.unblock(remote_identity.id, local_identity.id)
      {:ok, :unblocked}
    end
  end

  defp undo_block(_, _), do: {:error, :invalid_undo_block}

  # --- Flag (Report) ---

  defp handle_flag(%{"actor" => actor_ap_id, "object" => objects} = activity)
       when is_binary(actor_ap_id) do
    content = activity["content"] || ""
    reported_objects = if is_list(objects), do: objects, else: [objects]

    # The first URI is typically the reported actor, remaining are specific posts
    {reported_actor_uri, _post_uris} =
      case reported_objects do
        [actor_uri | rest] -> {actor_uri, rest}
        [] -> {nil, []}
      end

    with {:ok, remote_reporter} <- resolve_or_create_remote_identity(actor_ap_id),
         {:ok, reported_identity} <- resolve_reported_identity(reported_actor_uri) do
      Hybridsocial.Moderation.create_report(remote_reporter.id, %{
        "reported_id" => reported_identity.id,
        "category" => "other",
        "description" => content,
        "federated" => true
      })
    end
  end

  defp handle_flag(_), do: {:error, :invalid_flag_activity}

  defp resolve_reported_identity(nil), do: {:error, :no_reported_actor}

  defp resolve_reported_identity(ap_id) do
    # Try local first, then remote
    case extract_local_identity_id(ap_id) do
      nil ->
        case Repo.one(from(i in Identity, where: i.ap_actor_url == ^ap_id)) do
          nil -> {:error, :reported_identity_not_found}
          identity -> {:ok, identity}
        end

      id ->
        case Accounts.get_identity(id) do
          nil -> {:error, :reported_identity_not_found}
          identity -> {:ok, identity}
        end
    end
  end

  # --- Add (Pin) ---

  defp handle_add(%{"actor" => _actor, "object" => object, "target" => target})
       when is_binary(target) do
    if String.contains?(to_string(target), "/collections/featured") do
      case get_post_by_ap_id(to_string(object)) do
        nil -> {:error, :not_found}
        post -> post |> Ecto.Changeset.change(is_pinned: true) |> Repo.update()
      end
    else
      {:ok, :ignored}
    end
  end

  defp handle_add(_), do: {:error, :invalid_add_activity}

  # --- Remove (Unpin) ---

  defp handle_remove(%{"actor" => _actor, "object" => object, "target" => target})
       when is_binary(target) do
    if String.contains?(to_string(target), "/collections/featured") do
      case get_post_by_ap_id(to_string(object)) do
        nil -> {:error, :not_found}
        post -> post |> Ecto.Changeset.change(is_pinned: false) |> Repo.update()
      end
    else
      {:ok, :ignored}
    end
  end

  defp handle_remove(_), do: {:error, :invalid_remove_activity}

  # --- Helper functions ---

  defp resolve_local_identity(ap_id) when is_binary(ap_id) do
    case extract_local_identity_id(ap_id) do
      nil ->
        {:error, :not_local_actor}

      id ->
        case Accounts.get_identity(id) do
          nil -> {:error, :identity_not_found}
          identity -> {:ok, identity}
        end
    end
  end

  defp extract_local_identity_id(ap_id) do
    base = HybridsocialWeb.Endpoint.url()

    case String.replace_prefix(ap_id, "#{base}/actors/", "") do
      ^ap_id -> nil
      id -> id
    end
  end

  @doc """
  Resolves a remote actor to a local identity row.

  Both local and federated actors share the `identities` table —
  remote ones are distinguished by `ap_actor_url` being set. This is
  a deliberate single-table model (vs Mastodon's split accounts +
  account_aliases tables); it simplifies queries that span both
  sides of the local/remote boundary.
  """
  def resolve_remote_identity(ap_id) when is_binary(ap_id) do
    case Repo.one(from(i in Identity, where: i.ap_actor_url == ^ap_id)) do
      nil -> {:error, :remote_identity_not_found}
      identity -> {:ok, identity}
    end
  end

  @doc """
  Returns the existing identity row for the AP ID, or creates a new
  one by fetching the remote actor JSON. Enriches existing rows when
  display_name is missing (handles the case where we previously
  observed a bare AP ID via mention or follower list before ever
  resolving the full profile).
  """
  def resolve_or_create_remote_identity(ap_id) when is_binary(ap_id) do
    case Repo.one(from(i in Identity, where: i.ap_actor_url == ^ap_id)) do
      nil ->
        create_remote_identity(ap_id)

      %Identity{display_name: nil} = identity ->
        # Existing stub with no profile data — try to enrich it
        enrich_remote_identity(identity)

      %Identity{display_name: ""} = identity ->
        enrich_remote_identity(identity)

      identity ->
        {:ok, identity}
    end
  end

  defp enrich_remote_identity(identity) do
    case fetch_remote_actor_profile(identity.ap_actor_url) do
      %{display_name: name} = profile when is_binary(name) ->
        identity
        |> Ecto.Changeset.change(%{
          display_name: profile[:display_name],
          bio: profile[:bio],
          avatar_url: profile[:avatar_url],
          header_url: profile[:header_url],
          emojis: profile[:emojis] || [],
          profile_url: profile[:profile_url] || identity.profile_url,
          inbox_url: profile[:inbox_url] || identity.inbox_url,
          outbox_url: profile[:outbox_url] || identity.outbox_url,
          followers_url: profile[:followers_url] || identity.followers_url
        })
        |> Repo.update()

      _ ->
        {:ok, identity}
    end
  end

  @doc """
  Re-fetch a remote actor and refresh its profile fields, including the
  `emojis` and `profile_url` columns that older federated rows predate.
  Used by the one-off backfill task. No-op for local identities and on a
  failed fetch (keeps existing values).
  """
  def reenrich_remote_identity(%Identity{is_local: false} = identity) do
    case fetch_remote_actor_profile(identity.ap_actor_url) do
      %{display_name: name} = profile when is_binary(name) ->
        identity
        |> Ecto.Changeset.change(%{
          display_name: profile[:display_name] || identity.display_name,
          bio: profile[:bio] || identity.bio,
          avatar_url: profile[:avatar_url] || identity.avatar_url,
          header_url: profile[:header_url] || identity.header_url,
          emojis: profile[:emojis] || [],
          profile_url: profile[:profile_url] || identity.profile_url
        })
        |> Repo.update()

      _ ->
        {:ok, identity}
    end
  end

  def reenrich_remote_identity(identity), do: {:ok, identity}

  defp create_remote_identity(ap_id) do
    domain = ActivityMapper.extract_domain(ap_id)
    handle = generate_remote_handle(ap_id, domain)
    id = Ecto.UUID.generate()

    # Try to fetch the full actor profile for display name, avatar, bio
    remote_profile = fetch_remote_actor_profile(ap_id)

    attrs = %{
      id: id,
      type: "user",
      handle: handle,
      ap_actor_url: ap_id,
      # A federated actor row — we don't hold its key and never sign as
      # it. Must be explicit: the column defaults to true for local users.
      is_local: false,
      display_name: remote_profile[:display_name],
      bio: remote_profile[:bio],
      avatar_url: remote_profile[:avatar_url],
      header_url: remote_profile[:header_url],
      emojis: remote_profile[:emojis] || [],
      profile_url: remote_profile[:profile_url],
      inbox_url: remote_profile[:inbox_url] || "#{ap_id}/inbox",
      outbox_url: remote_profile[:outbox_url] || "#{ap_id}/outbox",
      followers_url: remote_profile[:followers_url] || "#{ap_id}/followers"
    }

    %Identity{}
    |> Ecto.Changeset.cast(attrs, [
      :id,
      :type,
      :handle,
      :ap_actor_url,
      :is_local,
      :display_name,
      :bio,
      :avatar_url,
      :header_url,
      :emojis,
      :profile_url,
      :inbox_url,
      :outbox_url,
      :followers_url
    ])
    |> Ecto.Changeset.validate_required([:type, :handle])
    |> Ecto.Changeset.unique_constraint(:handle)
    |> Repo.insert()
  end

  defp fetch_remote_actor_profile(ap_id) do
    # Try unsigned AP fetch, then signed, then Mastodon API lookup as last resort
    case fetch_actor_json(ap_id, _signed = false) do
      {:ok, actor} ->
        parse_actor_profile(actor)

      {:error, :unauthorized} ->
        case fetch_actor_json(ap_id, _signed = true) do
          {:ok, actor} ->
            parse_actor_profile(actor)

          _ ->
            # Signed fetch also failed — try Mastodon API as fallback
            fetch_profile_via_api(ap_id)
        end

      _ ->
        # Network error — try API fallback
        fetch_profile_via_api(ap_id)
    end
  end

  defp fetch_profile_via_api(ap_id) do
    # Extract domain and username from AP ID like "https://example.com/users/username"
    parsed = URI.parse(ap_id)
    domain = parsed.host

    username =
      case parsed.path do
        nil -> nil
        path -> path |> String.split("/") |> List.last()
      end

    if domain && username do
      url = "https://#{domain}/api/v1/accounts/lookup?acct=#{username}"

      # Mastodon REST API (NOT ActivityPub). Last-ditch fallback for
      # peers whose AP actor JSON we couldn't fetch. Mastodon's
      # /api/v1/accounts/lookup is unauthenticated by design — don't
      # signed-fetch this.
      headers = [
        {"Accept", "application/json"},
        {"User-Agent", Hybridsocial.Instance.user_agent()}
      ]

      case Hybridsocial.HTTP.get(url, headers, recv_timeout: 10_000, timeout: 10_000) do
        {:ok, %{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, account} ->
              %{
                display_name: account["display_name"],
                bio: account["note"],
                avatar_url: account["avatar"],
                header_url: account["header"],
                inbox_url: nil,
                outbox_url: nil,
                followers_url: nil
              }

            _ ->
              %{}
          end

        _ ->
          %{}
      end
    else
      %{}
    end
  end

  # Explicitly unsigned variant. The cascade in `fetch_remote_actor_profile`
  # tries this first to avoid a wasted round-trip on peers that don't run
  # secure mode; on 401/403 the caller falls back to `fetch_actor_json(url, true)`
  # which signed-fetches via SignedFetch.
  defp fetch_actor_json(url, false) do
    headers = [
      {"Accept", "application/activity+json, application/ld+json"},
      {"User-Agent", Hybridsocial.Instance.user_agent()}
    ]

    case Hybridsocial.HTTP.get(url, headers,
           recv_timeout: 10_000,
           timeout: 10_000,
           follow_redirect: true
         ) do
      {:ok, %{status_code: 200, body: body}} ->
        Jason.decode(body)

      {:ok, %{status_code: status}} when status in [401, 403] ->
        {:error, :unauthorized}

      _ ->
        {:error, :fetch_failed}
    end
  end

  # Signed-fetch path. Goes through SignedFetch which signs with the
  # instance actor — using a random user identity (the previous
  # implementation) leaked one user's identity into every cross-instance
  # lookup and broke when that user was later deleted.
  defp fetch_actor_json(url, true) do
    case Hybridsocial.Federation.SignedFetch.get(url, recv_timeout: 10_000, timeout: 10_000) do
      {:ok, %{status_code: 200, body: body}} ->
        Jason.decode(body)

      {:ok, %{status_code: status}} ->
        require Logger
        Logger.warning("Signed fetch failed for #{url}: HTTP #{status}")
        {:error, :signed_fetch_failed}

      {:error, reason} ->
        require Logger
        Logger.warning("Signed fetch error for #{url}: #{inspect(reason)}")
        {:error, :signed_fetch_failed}
    end
  end

  # An AP actor's icon/image is usually %{"url" => "..."} but peers ship it
  # as a bare URL string, a list, or junk. get_in/2 raises on a non-map
  # ("Access ... got: <string>"), so extract defensively.
  defp actor_media_url(%{"url" => url}) when is_binary(url), do: url
  defp actor_media_url([first | _]), do: actor_media_url(first)
  defp actor_media_url(url) when is_binary(url), do: url
  defp actor_media_url(_), do: nil

  defp parse_actor_profile(actor) do
    %{
      display_name: actor["name"],
      bio: actor["summary"],
      avatar_url: actor_media_url(actor["icon"]),
      header_url: actor_media_url(actor["image"]),
      # Custom emoji manifest for the display_name/bio, and the human HTML
      # profile URL (for "view on original instance").
      emojis: ActivityMapper.extract_emojis(actor["tag"]),
      profile_url: ActivityMapper.normalize_profile_url(actor["url"]),
      inbox_url: actor["inbox"],
      outbox_url: actor["outbox"],
      followers_url: actor["followers"]
    }
  end

  defp generate_remote_handle(ap_id, domain) do
    # Try to extract username from common AP ID patterns
    path =
      case URI.parse(ap_id) do
        %URI{path: path} when is_binary(path) -> path
        _ -> ""
      end

    username =
      path
      |> String.split("/")
      |> List.last()
      |> String.replace(~r/[^a-zA-Z0-9_]/, "")

    suffix = (domain || "unknown") |> String.replace(~r/[^a-zA-Z0-9]/, "") |> String.slice(0, 8)
    short_id = :crypto.strong_rand_bytes(3) |> Base.encode16(case: :lower)

    name = if username != "", do: username, else: "remote"
    "#{name}_#{suffix}_#{short_id}" |> String.slice(0, 30)
  end

  defp resolve_local_post(ap_id) when is_binary(ap_id) do
    # First try to find by ap_id (for federated posts)
    case get_post_by_ap_id(ap_id) do
      nil ->
        # Try to extract local post ID from URL
        case extract_local_post_id(ap_id) do
          nil ->
            {:error, :post_not_found}

          id ->
            case Hybridsocial.Social.Posts.get_post(id) do
              nil -> {:error, :post_not_found}
              post -> {:ok, post}
            end
        end

      post ->
        {:ok, post}
    end
  end

  defp extract_local_post_id(ap_id) do
    base = HybridsocialWeb.Endpoint.url()

    case String.replace_prefix(ap_id, "#{base}/objects/", "") do
      ^ap_id -> nil
      id -> id
    end
  end

  defp get_post_by_ap_id(nil), do: nil

  defp get_post_by_ap_id(ap_id) do
    Post
    |> where([p], p.ap_id == ^ap_id and is_nil(p.deleted_at))
    |> Repo.one()
  end

  defp resolve_parent_post_id(nil), do: nil

  defp resolve_parent_post_id(parent_ap_id) do
    case get_post_by_ap_id(parent_ap_id) do
      nil ->
        case extract_local_post_id(parent_ap_id) do
          nil -> nil
          id -> id
        end

      post ->
        post.id
    end
  end

  defp maybe_put_parent(attrs, nil), do: attrs
  defp maybe_put_parent(attrs, parent_id), do: Map.put(attrs, "parent_id", parent_id)

  defp schedule_thread_backfill(post_id, parent_ap_id) do
    Task.Supervisor.start_child(
      Hybridsocial.TaskSupervisor,
      fn -> backfill_thread(post_id, parent_ap_id) end
    )
  end

  defp backfill_thread(child_post_id, parent_ap_id, depth \\ 0) do
    # Limit depth to prevent infinite recursion
    if depth >= 10 do
      Logger.warning("Thread backfill: max depth reached for #{parent_ap_id}")
      :ok
    else
      case ObjectResolver.resolve(parent_ap_id) do
        {:ok, object} ->
          case handle_backfilled_object(object, child_post_id) do
            {:ok, parent_post, grandparent_ap_id} ->
              # Continue walking up the chain if there's a grandparent
              if grandparent_ap_id do
                backfill_thread(parent_post.id, grandparent_ap_id, depth + 1)
              else
                :ok
              end

            _ ->
              :ok
          end

        {:error, reason} ->
          Logger.warning("Thread backfill failed for #{parent_ap_id}: #{inspect(reason)}")
          :ok
      end
    end
  end

  defp handle_backfilled_object(object, child_post_id) do
    ap_id = object["id"]

    # Don't re-import if we already have it
    case get_post_by_ap_id(ap_id) do
      nil ->
        post_attrs = ActivityMapper.to_post(object)
        actor_ap_id = object["attributedTo"] || object["actor"]

        case resolve_or_create_remote_identity(actor_ap_id) do
          {:ok, remote_identity} ->
            grandparent_ap_id = post_attrs["parent_ap_id"]
            grandparent_id = resolve_parent_post_id(grandparent_ap_id)

            insert_attrs =
              post_attrs
              |> Map.delete("parent_ap_id")
              |> Map.put("identity_id", remote_identity.id)
              |> Map.put("parent_ap_id", grandparent_ap_id)
              |> maybe_put_parent(grandparent_id)
              |> Posts.maybe_resolve_root_id()

            case %Post{}
                 |> Post.create_changeset(insert_attrs, has_media: remote_media?(object))
                 |> maybe_put_published_at(post_attrs["published_at"])
                 |> maybe_put_content_html(post_attrs["content_html"])
                 |> Repo.insert() do
              {:ok, parent_post} ->
                # Persist any media attachments from the backfilled
                # parent post too — same proxy-on-demand model.
                persist_remote_attachments(parent_post, object, remote_identity)
                # Link its hashtags as well, so a post that entered our DB
                # by being fetched as a thread ancestor still gets its tag
                # chips and can trend — the inbox-delivery path does this,
                # but this backfill path used to skip it (posts showed
                # inline #tags with no extracted chips).
                persist_remote_hashtags(parent_post, object)
                # Link the child post to this newly fetched parent
                link_child_to_parent(child_post_id, parent_post)
                {:ok, parent_post, grandparent_ap_id}

              error ->
                error
            end

          error ->
            error
        end

      existing_parent ->
        # Parent already exists, just link the child
        link_child_to_parent(child_post_id, existing_parent)
        {:ok, existing_parent, nil}
    end
  end

  defp link_child_to_parent(child_post_id, parent_post) do
    root_id = parent_post.root_id || parent_post.id

    Post
    |> where([p], p.id == ^child_post_id)
    |> Repo.update_all(set: [parent_id: parent_post.id, root_id: root_id])

    # Also update any other orphaned posts that reference this parent via parent_ap_id
    if parent_post.ap_id do
      Post
      |> where([p], p.parent_ap_id == ^parent_post.ap_id and is_nil(p.parent_id))
      |> Repo.update_all(set: [parent_id: parent_post.id, root_id: root_id])
    end
  end

  defp maybe_put_content_html(changeset, nil), do: changeset

  defp maybe_put_content_html(changeset, content_html) do
    # Override the escaped HTML with the raw HTML from the AP object
    Ecto.Changeset.put_change(changeset, :content_html, content_html)
  end

  defp maybe_put_published_at(changeset, nil), do: changeset

  defp maybe_put_published_at(changeset, published_at) do
    published_at = DateTime.truncate(published_at, :microsecond)
    edit_expires = DateTime.add(published_at, 86400, :second) |> DateTime.truncate(:microsecond)

    changeset
    |> Ecto.Changeset.put_change(:published_at, published_at)
    |> Ecto.Changeset.put_change(:edit_expires_at, edit_expires)
    # Remote posts arrive with their authoring timestamp; seed
    # `last_activity_at` with it so the thread sorts in its natural
    # chronological slot. Replies to known local roots will bump those
    # roots separately below.
    |> Ecto.Changeset.put_change(:last_activity_at, published_at)
  end

  defp normalize_object(%{"id" => id}) when is_binary(id), do: %{"id" => id}
  defp normalize_object(id) when is_binary(id), do: %{"id" => id}
  defp normalize_object(other), do: other

  defp normalize_object_id(%{"id" => id}) when is_binary(id), do: id
  defp normalize_object_id(id) when is_binary(id), do: id
  defp normalize_object_id(_), do: nil

  defp find_pending_follow(%{"id" => _follow_ap_id}, followee_id) do
    # Find the most recent follow row for this (follower, followee).
    # We accept BOTH `:pending` (manual-approval flow) and `:accepted`
    # (auto-accept flow) — the latter happens when our local actor is
    # not locked: we created the follow as already-accepted, then
    # Mastodon's confirmation Accept arrives and would otherwise
    # log `:follow_not_found`. Treating accepted-arrival as a no-op
    # makes the Accept handler idempotent.
    follow =
      Hybridsocial.Social.Follow
      |> where([f], f.followee_id == ^followee_id and f.status in [:pending, :accepted])
      |> order_by([f], desc: f.inserted_at)
      |> limit(1)
      |> Repo.one()

    case follow do
      nil -> {:error, :follow_not_found}
      follow -> {:ok, follow}
    end
  end

  defp find_pending_follow(_, _), do: {:error, :invalid_follow_reference}

  # --- Move ---

  defp handle_move(activity) do
    Hybridsocial.Federation.Migration.process_move(activity)
  end

  defp update_remote_post(object, remote_identity) do
    case get_post_by_ap_id(object["id"]) do
      %Post{identity_id: identity_id} = post when identity_id == remote_identity.id ->
        # Remote peers send HTML in the AP `content` field, so the
        # plaintext column is the stripped version and the rendered
        # column is the raw HTML — same split the create path uses
        # in `Federation.ActivityMapper.to_post_base/1`. Without
        # this, the markdown sanitizer in `Post.edit_changeset`
        # would escape the HTML markup and the post would render
        # with literal `<span>` tags after every remote edit.
        raw_html = object["content"]
        plaintext = Hybridsocial.Content.HtmlStripper.to_plaintext(raw_html)

        attrs = %{
          "content" => plaintext,
          "content_html" => raw_html,
          "sensitive" => object["sensitive"] || false,
          "spoiler_text" => object["summary"]
        }

        case post
             |> Post.edit_changeset(attrs, has_media: remote_media?(object))
             |> Repo.update() do
          {:ok, updated_post} = ok ->
            # Mirror the local edit broadcast (Posts.edit_post/4)
            # so a local user replying to a remote post also gets
            # the live "edited" indicator when the origin author
            # ships an Update activity.
            Phoenix.PubSub.broadcast(
              Hybridsocial.PubSub,
              "post:#{updated_post.id}",
              %{
                event: "edit",
                payload: %{id: updated_post.id, edited_at: updated_post.edited_at}
              }
            )

            ok

          err ->
            err
        end

      %Post{} ->
        {:error, :forbidden}

      nil ->
        {:error, :post_not_found}
    end
  end

  # ---------------------------------------------------------------------------
  # Direct message ingest
  # ---------------------------------------------------------------------------

  defp handle_direct_message(actor_ap_id, object) do
    with {:ok, sender} <- resolve_or_create_remote_identity(actor_ap_id),
         {:ok, recipient} <- find_local_recipient(object) do
      plaintext = Hybridsocial.Content.HtmlStripper.to_plaintext(object["content"])

      case Hybridsocial.Messaging.ingest_remote_dm(sender, recipient, %{
             content: plaintext,
             ap_id: object["id"],
             in_reply_to: object["inReplyTo"],
             published: object["published"]
           }) do
        {:ok, message} ->
          Logger.info(
            "Ingested DM from #{actor_ap_id} into conversation #{message.conversation_id}"
          )

          {:ok, message}

        {:error, reason} = err ->
          Logger.warning("DM ingest failed for #{actor_ap_id}: #{inspect(reason)}")
          err
      end
    end
  end

  # Find the local identity the DM is addressed to — prefers Mention
  # tags (explicit targets), falls back to scanning `to`/`cc` for an
  # actor URL on our domain.
  defp find_local_recipient(object) do
    candidates =
      (object |> Map.get("tag", []) |> List.wrap() |> Enum.flat_map(&mention_href/1)) ++
        List.wrap(object["to"]) ++
        List.wrap(object["cc"])

    candidates
    |> Enum.uniq()
    |> Enum.find_value({:error, :no_local_recipient}, fn url ->
      case lookup_local_identity(url) do
        nil -> false
        identity -> {:ok, identity}
      end
    end)
  end

  defp mention_href(%{"type" => "Mention", "href" => href}) when is_binary(href), do: [href]
  defp mention_href(_), do: []

  # The href we resolve here is the recipient of a DM Mention — it
  # must point at one of OUR actors. A fallback by `ap_actor_url`
  # would also match remote rows (identical URL) and accidentally
  # deliver the DM into a remote user's local mirror, so we only
  # accept the local prefix form.
  defp lookup_local_identity(url) when is_binary(url) do
    if Hybridsocial.Federation.LocalUrl.local_actor_url?(url) do
      id = String.replace_prefix(url, Hybridsocial.Federation.LocalUrl.actor_prefix(), "")
      Repo.get(Identity, id)
    end
  end

  defp lookup_local_identity(_), do: nil
end
