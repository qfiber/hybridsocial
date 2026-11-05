defmodule HybridsocialWeb.Api.V1.StatusController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Social.Posts
  alias Hybridsocial.Premium.TierLimits
  alias HybridsocialWeb.Compat
  alias HybridsocialWeb.Serializers.Mastodon
  alias HybridsocialWeb.Serializers.PostSerializer

  # The reaction a Mastodon `favourite` maps to. Reactions are our superset
  # of favourites; a client that only knows about stars gets the plain one.
  @favourite_reaction "like"

  # POST /api/v1/statuses
  def create(conn, params) do
    identity = conn.assigns.current_identity
    # `status`, `in_reply_to_id`, `visibility: private` and the nested poll
    # params are Mastodon's spelling of fields we already have. Accepting them
    # for every caller costs the frontend nothing and is what lets a
    # third-party client post at all.
    params = Mastodon.normalize_status_params(params)
    limits = TierLimits.limits_for(identity)

    with :ok <- validate_tier_limits(params, limits),
         :ok <- check_bot_rate_limit(identity),
         {:ok, author_id} <- Hybridsocial.Pages.resolve_post_author(params, identity.id) do
      case Posts.create_post(author_id, params, identity) do
        {:ok, post} ->
          post = Hybridsocial.Repo.preload(post, [:identity, :quote])

          conn
          |> put_status(:created)
          |> Compat.json(serialize_post(conn, post), :status)

        {:error, :premium_emojis_required, shortcodes} ->
          conn
          |> put_status(:forbidden)
          |> json(%{error: "premium_emojis_required", shortcodes: shortcodes})

        {:error, :audio_not_allowed} ->
          conn
          |> put_status(:forbidden)
          |> json(%{
            error: "audio_not_allowed",
            message: "Your current tier does not allow audio posts."
          })

        {:error, :target_media_not_found} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "target_media.not_found"})

        {:error, :target_media_mismatch} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "target_media.not_on_parent"})

        {:error, :target_media_requires_parent} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "target_media.requires_parent"})

        {:error, :group_forbidden} ->
          conn
          |> put_status(:forbidden)
          |> json(%{error: "group.forbidden"})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "validation.failed", details: format_errors(changeset)})
      end
    else
      {:error, :page_forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "page.forbidden"})

      {:error, error_key, max} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: error_key, max: max})
    end
  end

  @doc """
  POST /api/v1/statuses/by_ids
  Body: {ids: [uuid, ...]}

  Batch-fetch up to 100 posts by ID. Used by the client-side "Seen
  posts today" history page so it can render many posts without
  making one request per entry. Missing or soft-deleted IDs are
  omitted from the response; the caller is expected to reconcile
  against their own list.
  """
  def by_ids(conn, params) do
    ids =
      case params do
        %{"ids" => ids} when is_list(ids) -> ids
        _ -> []
      end

    viewer_id = current_identity_id(conn)

    posts =
      ids
      |> Posts.list_posts_by_ids()
      |> Enum.filter(&Posts.viewer_can_read?(&1, viewer_id))

    Compat.json(conn, Enum.map(posts, &serialize_post(conn, &1)), :statuses)
  end

  # GET /api/v1/statuses/:id
  def show(conn, %{"id" => id}) do
    viewer_id =
      case conn.assigns[:current_identity] do
        %{id: vid} -> vid
        _ -> nil
      end

    case Posts.get_post_with_context_for_viewer(id, viewer_id) do
      nil ->
        # 404 both for missing and for "you can't see this" — we
        # don't want probing to distinguish "post doesn't exist"
        # from "this is a direct post not addressed to you".
        conn
        |> put_status(:not_found)
        |> json(%{error: "status.not_found"})

      post ->
        if Hybridsocial.Accounts.hidden_from_viewer?(
             Hybridsocial.Repo.preload(post, :identity).identity,
             viewer_id
           ) do
          conn |> put_status(:not_found) |> json(%{error: "status.not_found"})
        else
          conn
          |> put_status(:ok)
          |> Compat.json(serialize_post(conn, post), :status)
        end
    end
  end

  # PUT /api/v1/statuses/:id
  def update(conn, %{"id" => id} = params) do
    identity = conn.assigns.current_identity

    case Posts.edit_post(id, identity.id, params, identity) do
      {:ok, post} ->
        post = Hybridsocial.Repo.preload(post, [:identity, :quote])

        conn
        |> put_status(:ok)
        |> Compat.json(serialize_post(conn, post), :status)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "status.not_found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "status.forbidden"})

      {:error, :premium_emojis_required, shortcodes} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "premium_emojis_required", shortcodes: shortcodes})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  # DELETE /api/v1/statuses/:id
  def delete(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity

    case Posts.delete_post(id, identity.id) do
      {:ok, _post} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "status.deleted"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "status.not_found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "status.forbidden"})
    end
  end

  # GET /api/v1/statuses/:id/history
  def history(conn, %{"id" => id}) do
    viewer_id = current_identity_id(conn)

    case Posts.get_post_for_viewer(id, viewer_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "status.not_found"})

      _post ->
        revisions = Posts.get_revisions(id)

        conn
        |> put_status(:ok)
        |> json(Enum.map(revisions, &serialize_revision/1))
    end
  end

  @valid_reaction_types ~w(like love care angry sad lol wow)

  # POST /api/v1/statuses/:id/translate
  def translate(conn, %{"id" => id} = params) do
    target_lang = params["target_lang"] || "en"
    viewer_id = current_identity_id(conn)

    case Posts.get_post_for_viewer(id, viewer_id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "status.not_found"})

      post ->
        text = post.content || ""

        case Hybridsocial.Content.Translation.translate(text, target_lang) do
          {:ok, translated} ->
            json(conn, %{
              content: translated,
              detected_source_language: post.language,
              provider: Hybridsocial.Config.get("translation_backend", "none")
            })

          {:error, :translation_disabled} ->
            conn |> put_status(:service_unavailable) |> json(%{error: "translation.disabled"})

          {:error, reason} ->
            conn
            |> put_status(:bad_gateway)
            |> json(%{error: "translation.failed", detail: inspect(reason)})
        end
    end
  end

  # GET /api/v1/statuses/:id/reactions
  def reactions(conn, %{"id" => id}) do
    import Ecto.Query

    viewer_id = current_identity_id(conn)

    case Posts.get_post_for_viewer(id, viewer_id) do
      nil ->
        # Match `show`: uniform 404 so enumerating reactions can't
        # confirm the existence of a direct post the viewer isn't
        # party to.
        conn |> put_status(:not_found) |> json(%{error: "status.not_found"})

      _post ->
        reactions =
          Hybridsocial.Social.Reaction
          |> where([r], r.post_id == ^id)
          |> preload(:identity)
          |> Hybridsocial.Repo.all()

        grouped =
          reactions
          |> Enum.group_by(& &1.type)
          |> Enum.map(fn {type, entries} ->
            %{
              type: type,
              count: length(entries),
              accounts:
                Enum.map(entries, fn r ->
                  %{
                    id: r.identity.id,
                    handle: r.identity.handle,
                    display_name: r.identity.display_name,
                    avatar_url: r.identity.avatar_url
                  }
                end)
            }
          end)
          |> Enum.sort_by(& &1.count, :desc)

        json(conn, grouped)
    end
  end

  # POST /api/v1/statuses/:id/react
  def react(conn, %{"id" => id} = params) do
    identity = conn.assigns.current_identity
    type = Map.get(params, "type", "like")
    custom_emoji_allowed = Hybridsocial.Premium.TierLimits.limit(identity, :custom_emoji) == true

    is_custom_emoji = String.starts_with?(type, ":") and String.ends_with?(type, ":")
    # Premium reactions are bare shortcodes from the admin-curated
    # catalog (e.g. "fire"). The picker sends them without colons —
    # before this branch we 422'd them as invalid_type.
    is_premium_reaction =
      not is_custom_emoji and type not in @valid_reaction_types and
        Hybridsocial.Reactions.premium_reaction?(type)

    is_valid =
      type in @valid_reaction_types or
        (is_custom_emoji and custom_emoji_allowed) or
        (is_premium_reaction and custom_emoji_allowed)

    cond do
      not is_valid ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "reaction.invalid_type", valid_types: @valid_reaction_types})

      is_custom_emoji ->
        # Verify custom emoji exists
        shortcode = String.trim(type, ":")

        case Hybridsocial.Repo.get_by(Hybridsocial.Content.CustomEmoji,
               shortcode: shortcode,
               enabled: true
             ) do
          nil ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "reaction.emoji_not_found"})

          _emoji ->
            do_react(conn, id, identity.id, type, custom_emoji_allowed, params)
        end

      true ->
        # Standard reaction or premium-catalog shortcode — both are
        # bare strings of `[a-z]+` and pass `Reaction.changeset`'s
        # custom_emoji_allowed format when the user is premium.
        do_react(conn, id, identity.id, type, custom_emoji_allowed, params)
    end
  end

  defp do_react(conn, post_id, identity_id, type, custom_emoji_allowed, params) do
    target_media_id = blank_to_nil(Map.get(params, "target_media_id"))

    opts = [
      custom_emoji_allowed: custom_emoji_allowed,
      target_media_id: target_media_id
    ]

    case Posts.react(post_id, identity_id, type, opts) do
      {:ok, reaction} ->
        conn
        |> put_status(:ok)
        |> json(%{
          id: reaction.id,
          type: reaction.type,
          post_id: reaction.post_id,
          target_media_id: reaction.target_media_id
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "status.not_found"})

      {:error, :group_forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "group.forbidden"})

      {:error, :target_media_not_found} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "reaction.target_media_not_found"})

      {:error, :target_media_mismatch} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "reaction.target_media_mismatch"})

      {:error, :target_media_invalid} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "reaction.target_media_invalid"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v) when is_binary(v), do: v
  defp blank_to_nil(_), do: nil

  # DELETE /api/v1/statuses/:id/react
  def unreact(conn, %{"id" => id} = params) do
    identity = conn.assigns.current_identity
    target_media_id = blank_to_nil(Map.get(params, "target_media_id"))

    case Posts.unreact(id, identity.id, target_media_id) do
      {:ok, _} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "reaction.removed"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "reaction.not_found"})
    end
  end

  # POST /api/v1/statuses/:id/boost
  def boost(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity

    case Posts.boost(id, identity.id) do
      {:ok, _boost} ->
        post = Posts.get_post(id)

        conn
        |> put_status(:ok)
        |> Compat.json(serialize_post(conn, post), :status)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "status.not_found"})

      {:error, :boost_not_allowed} ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          error: "status.boost_not_allowed",
          message: "This post's audience can't be widened by a boost."
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  # DELETE /api/v1/statuses/:id/boost
  def unboost(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity

    case Posts.unboost(id, identity.id) do
      {:ok, _} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "boost.removed"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "boost.not_found"})
    end
  end

  # GET /api/v1/statuses/:id/context
  #
  # Optional `media_id` query param narrows the descendants to those
  # that pinned themselves to a specific image on the focused post.
  # Ancestors are never filtered — the parent context is always the
  # full lineage. Pass `media_id=none` to fetch only post-level
  # replies (target_media_id IS NULL).
  def context(conn, %{"id" => id} = params) do
    identity_id = current_identity_id(conn)
    media_filter = parse_media_filter(params["media_id"])

    # Gate at the thread root: if the focused post is a direct one the
    # viewer isn't party to, don't leak its ancestors or replies.
    case Posts.get_post_for_viewer(id, identity_id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "status.not_found"})

      _post ->
        fetch_thread(conn, id, identity_id, media_filter)
    end
  end

  defp parse_media_filter(nil), do: :all
  defp parse_media_filter(""), do: :all
  defp parse_media_filter("none"), do: :none
  defp parse_media_filter(id) when is_binary(id), do: {:media, id}
  defp parse_media_filter(_), do: :all

  # The thread is rooted at `focused_id`. Filtering applies to direct
  # replies of that root only — nested grandchild replies inherit
  # their parent's audience (we don't try to track per-image
  # targeting deeper than depth 1, where it makes sense).
  defp filter_by_target_media(descendants, _focused_id, :all), do: descendants

  defp filter_by_target_media(descendants, focused_id, filter) do
    # Walk descendants once, keeping a running set of allowed parent
    # ids. A direct reply is kept iff it matches the filter; a nested
    # reply is kept iff its parent_id is already in the allowed set
    # (transitively pruning whole subtrees whose root direct reply was
    # filtered out).
    {kept, _allowed} =
      Enum.reduce(descendants, {[], MapSet.new([focused_id])}, fn p, {acc, allowed} ->
        cond do
          # Direct reply on the focused post — apply the filter.
          p.parent_id == focused_id ->
            if direct_reply_matches?(p, filter) do
              {[p | acc], MapSet.put(allowed, p.id)}
            else
              {acc, allowed}
            end

          # Nested: keep iff its parent passed the filter.
          MapSet.member?(allowed, p.parent_id) ->
            {[p | acc], MapSet.put(allowed, p.id)}

          true ->
            {acc, allowed}
        end
      end)

    Enum.reverse(kept)
  end

  defp direct_reply_matches?(post, :none), do: is_nil(Map.get(post, :target_media_id))

  defp direct_reply_matches?(post, {:media, media_id}),
    do: Map.get(post, :target_media_id) == media_id

  defp fetch_thread(conn, id, identity_id, media_filter) do
    case Posts.get_thread(id) do
      {:ok, %{ancestors: ancestors, descendants: descendants}} ->
        # Strip any post the viewer can't read — keeps direct replies
        # scoped to their audience even though the thread-root check
        # already gated entry.
        ancestors = Enum.filter(ancestors, &Posts.viewer_can_read?(&1, identity_id))

        descendants =
          descendants
          |> Enum.filter(&Posts.viewer_can_read?(&1, identity_id))
          |> filter_by_target_media(id, media_filter)

        serialized_ancestors =
          PostSerializer.serialize_many(ancestors, current_identity_id: identity_id)

        serialized_descendants =
          PostSerializer.serialize_many(descendants, current_identity_id: identity_id)

        # Insert tombstones for gaps (exclude the focused post itself)
        serialized_ancestors = insert_tombstones(serialized_ancestors, id)
        serialized_descendants = insert_descendant_tombstones(serialized_descendants, id)

        conn
        |> put_status(:ok)
        |> Compat.json(
          %{ancestors: serialized_ancestors, descendants: serialized_descendants},
          :context
        )

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "status.not_found"})
    end
  end

  # POST /api/v1/statuses/:id/pin
  def pin(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity

    case Posts.get_post(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "status.not_found"})

      %{deleted_at: deleted_at} when not is_nil(deleted_at) ->
        conn |> put_status(:not_found) |> json(%{error: "status.not_found"})

      post ->
        scope = Posts.pin_scope(post)
        max_pins = pin_limit_for(scope, identity)

        if Posts.pinned_count(scope) >= max_pins do
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "limits.max_pinned_posts", max: max_pins, scope: scope_name(scope)})
        else
          case Posts.pin_post(id, identity.id) do
            {:ok, pinned} ->
              pinned = Hybridsocial.Repo.preload(pinned, [:identity, :quote])

              conn
              |> put_status(:ok)
              |> Compat.json(serialize_post(conn, pinned), :status)

            {:error, :not_found} ->
              conn |> put_status(:not_found) |> json(%{error: "status.not_found"})

            {:error, :forbidden} ->
              conn |> put_status(:forbidden) |> json(%{error: "status.forbidden"})
          end
        end
    end
  end

  # Per-scope pin limits.
  #   * profile → user's tier allowance (`limits[:pinned_posts]`)
  #   * group / page → instance config (`max_pinned_in_group` /
  #     `max_pinned_on_page`, default 3 each). Hard-coding a default
  #     keeps the feature usable on instances that haven't surfaced
  #     these knobs in the admin UI yet.
  defp pin_limit_for({:profile, _}, identity) do
    limits = TierLimits.limits_for(identity)
    limits[:pinned_posts] || 1
  end

  defp pin_limit_for({:group, _}, _identity) do
    Hybridsocial.Config.get("max_pinned_in_group", 3)
  end

  defp pin_limit_for({:page, _}, _identity) do
    Hybridsocial.Config.get("max_pinned_on_page", 3)
  end

  defp scope_name({:profile, _}), do: "profile"
  defp scope_name({:group, _}), do: "group"
  defp scope_name({:page, _}), do: "page"

  # DELETE /api/v1/statuses/:id/pin
  def unpin(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity

    case Posts.unpin_post(id, identity.id) do
      {:ok, post} ->
        post = Hybridsocial.Repo.preload(post, [:identity, :quote])

        conn
        |> put_status(:ok)
        |> Compat.json(serialize_post(conn, post), :status)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "status.not_found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "status.forbidden"})
    end
  end

  # --- Mastodon action aliases ---
  #
  # Mastodon spells these differently (`favourite`, `reblog`, `unbookmark`)
  # and, unlike our native actions, every one of them answers with the full
  # status — that's what the client re-renders the row from. They're thin
  # wrappers over the same context calls rather than changes to the native
  # responses, which the web app depends on.

  # POST /api/v1/statuses/:id/favourite
  def favourite(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity

    case Posts.react(id, identity.id, @favourite_reaction, []) do
      {:ok, _reaction} -> respond_with_status(conn, id)
      {:error, :not_found} -> not_found(conn, "status.not_found")
      {:error, _} -> respond_with_status(conn, id)
    end
  end

  # POST /api/v1/statuses/:id/unfavourite
  def unfavourite(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity
    Posts.unreact(id, identity.id, nil)
    respond_with_status(conn, id)
  end

  # POST /api/v1/statuses/:id/reblog
  def reblog(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity

    case Posts.boost(id, identity.id) do
      {:ok, _boost} ->
        respond_with_status(conn, id)

      {:error, :not_found} ->
        not_found(conn, "status.not_found")

      {:error, :boost_not_allowed} ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          error: "status.boost_not_allowed",
          message: "This post's audience can't be widened by a boost."
        })

      # Already boosted: the client's intent is satisfied, so report the
      # current state rather than an error it has no way to act on.
      {:error, _changeset} ->
        respond_with_status(conn, id)
    end
  end

  # POST /api/v1/statuses/:id/unreblog
  def unreblog(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity
    Posts.unboost(id, identity.id)
    respond_with_status(conn, id)
  end

  # POST /api/v1/statuses/:id/unbookmark
  def unbookmark(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity
    Hybridsocial.Social.Bookmarks.unbookmark(identity.id, id)
    respond_with_status(conn, id)
  end

  defp respond_with_status(conn, id) do
    viewer_id = current_identity_id(conn)

    case Posts.get_post_with_context_for_viewer(id, viewer_id) do
      nil -> not_found(conn, "status.not_found")
      post -> conn |> put_status(:ok) |> Compat.json(serialize_post(conn, post), :status)
    end
  end

  defp not_found(conn, error), do: conn |> put_status(:not_found) |> json(%{error: error})

  # POST /api/v1/statuses/:id/view
  def view(conn, %{"id" => id} = params) do
    identity = conn.assigns[:current_identity]
    identity_id = if identity, do: identity.id, else: nil

    attrs = %{
      "watch_duration" => params["watch_duration"],
      "total_duration" => params["total_duration"],
      "completed" => params["completed"],
      "replayed" => params["replayed"],
      "source" => params["source"]
    }

    case Hybridsocial.Social.Streams.record_view(id, identity_id, attrs) do
      {:ok, view_record} ->
        conn
        |> put_status(:ok)
        |> json(%{
          id: view_record.id,
          post_id: view_record.post_id,
          watch_duration: view_record.watch_duration,
          total_duration: view_record.total_duration,
          completed: view_record.completed,
          replayed: view_record.replayed,
          source: view_record.source
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  # --- Serialization ---

  defp serialize_post(conn, post) do
    # Serializer reads post.identity (for badges, account block); preload
    # defensively here — Repo.preload is a no-op when already loaded.
    post = Hybridsocial.Repo.preload(post, :identity)
    PostSerializer.serialize(post, current_identity_id: current_identity_id(conn))
  end

  defp current_identity_id(conn) do
    case conn.assigns[:current_identity] do
      %{id: id} -> id
      _ -> nil
    end
  end

  # Insert tombstones for gaps in ancestor chain
  defp insert_tombstones(ancestors, focused_id) do
    known_ids = MapSet.new([focused_id | Enum.map(ancestors, & &1[:id])])

    ancestors
    |> Enum.reduce({[], nil}, fn post, {acc, _prev_id} ->
      parent = post[:parent_id]

      acc =
        if parent && !MapSet.member?(known_ids, parent) &&
             !Enum.any?(acc, fn p -> p[:id] == parent end) do
          [PostSerializer.serialize_tombstone(parent) | acc]
        else
          acc
        end

      {acc ++ [post], post[:id]}
    end)
    |> elem(0)
  end

  # Insert tombstones for orphaned descendants
  defp insert_descendant_tombstones(descendants, focused_id) do
    known_ids = MapSet.new([focused_id | Enum.map(descendants, & &1[:id])])

    Enum.flat_map(descendants, fn post ->
      parent = post[:parent_id]

      if parent && !MapSet.member?(known_ids, parent) do
        [PostSerializer.serialize_tombstone(parent), post]
      else
        [post]
      end
    end)
    |> Enum.uniq_by(& &1[:id])
  end

  defp serialize_revision(revision) do
    %{
      id: revision.id,
      content: revision.content,
      content_html: revision.content_html,
      edited_at: revision.edited_at,
      revision_number: revision.revision_number
    }
  end

  defp check_bot_rate_limit(identity) do
    import Ecto.Query

    # Priority: per-user override > bot-specific > global bot default > global user default
    limit =
      cond do
        # Admin per-user override (stored in identity metadata)
        is_map(identity.metadata) and is_integer(identity.metadata["posts_per_hour"]) ->
          identity.metadata["posts_per_hour"]

        # Bot-specific limit
        identity.is_bot ->
          bot = Hybridsocial.Repo.get(Hybridsocial.Accounts.Bot, identity.id)

          if bot && bot.posts_per_hour do
            bot.posts_per_hour
          else
            Hybridsocial.Config.get("bot_posts_per_hour", 30)
          end

        # Global user limit (0 = unlimited, default)
        true ->
          Hybridsocial.Config.get("user_posts_per_hour", 0)
      end

    # 0 or nil = unlimited
    if is_nil(limit) or limit == 0 do
      :ok
    else
      one_hour_ago = DateTime.add(DateTime.utc_now(), -3600, :second)

      count =
        Hybridsocial.Social.Post
        |> where(
          [p],
          p.identity_id == ^identity.id and p.inserted_at > ^one_hour_ago and is_nil(p.deleted_at)
        )
        |> Hybridsocial.Repo.aggregate(:count)

      if count >= limit do
        {:error, "limits.post_rate_limit", limit}
      else
        :ok
      end
    end
  end

  defp validate_tier_limits(params, limits) do
    media_ids = params["media_ids"] || []
    poll_options = params["options"] || []

    cond do
      length(media_ids) > limits[:media_per_post] ->
        {:error, "limits.media_per_post", limits[:media_per_post]}

      poll_options != [] and length(poll_options) > limits[:poll_options] ->
        {:error, "limits.poll_options", limits[:poll_options]}

      params["scheduled_at"] && !limits[:scheduled_posts] ->
        {:error, "limits.scheduled_posts_not_allowed", nil}

      true ->
        :ok
    end
  end

  # POST /api/v1/statuses/:id/mute
  def mute_post(conn, %{"id" => post_id}) do
    identity = conn.assigns.current_identity

    case Hybridsocial.Social.mute_post(post_id, identity.id) do
      {:ok, _} -> json(conn, %{status: "ok"})
      _ -> json(conn, %{status: "ok"})
    end
  end

  # DELETE /api/v1/statuses/:id/mute
  def unmute_post(conn, %{"id" => post_id}) do
    identity = conn.assigns.current_identity
    Hybridsocial.Social.unmute_post(post_id, identity.id)
    json(conn, %{status: "ok"})
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
