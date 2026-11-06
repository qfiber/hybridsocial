defmodule Hybridsocial.Notifications do
  @moduledoc """
  The Notifications context. Manages in-app notifications and notification preferences.
  """
  import Ecto.Query

  alias Hybridsocial.Repo
  alias Hybridsocial.Notifications.Notification
  alias Hybridsocial.Notifications.Preference

  # ---------------------------------------------------------------------------
  # Notifications CRUD
  # ---------------------------------------------------------------------------

  def create_notification(attrs) do
    recipient_id = attrs[:recipient_id] || attrs["recipient_id"]
    actor_id = attrs[:actor_id] || attrs["actor_id"]

    cond do
      recipient_id == actor_id ->
        {:ok, :skipped}

      Hybridsocial.Social.muted?(recipient_id, actor_id) ->
        {:ok, :skipped}

      true ->
        result =
          %Notification{}
          |> Notification.changeset(stringify_keys(attrs))
          |> Repo.insert()

        case result do
          {:ok, notification} ->
            # The in-app switch governs the live event, which is what rings the
            # bell and bumps the badge. The row still backs push and email.
            if should_notify?(recipient_id, notification.type, :in_app) do
              broadcast_to_user(notification)
            end

            maybe_deliver(notification, attrs, actor_id)
            # Bot owners can subscribe to events over an outbound
            # webhook; this is a no-op for human recipients and for
            # bots without a configured URL.
            Hybridsocial.Bots.Webhooks.maybe_enqueue_for_notification(notification, attrs)
            {:ok, notification}

          error ->
            error
        end
    end
  end

  # Fires the notification out over the user's SSE stream so the bell
  # badge + list update without a poll. Done at the central creation
  # point so every type that lands in the DB automatically reaches the
  # frontend; call sites don't need to remember to broadcast.
  defp broadcast_to_user(%Notification{} = notification) do
    notification = Repo.preload(notification, :actor)

    Phoenix.PubSub.broadcast(
      Hybridsocial.PubSub,
      "user:#{notification.recipient_id}",
      %{event: "notification", payload: serialize_for_stream(notification)}
    )
  end

  defp serialize_for_stream(%Notification{} = n) do
    %{
      id: n.id,
      type: n.type,
      read: n.read,
      target_type: n.target_type,
      target_id: n.target_id,
      created_at: n.inserted_at,
      reaction_type: stream_reaction_type(n),
      actor: HybridsocialWeb.Helpers.Account.serialize_summary(n.actor)
    }
  end

  # Look up the actor's current reaction emoji so the SSE push can
  # render the right glyph (👍 / ❤️ / 😂 / …) instead of falling back
  # to the generic thumb. Single row keyed on (post_id, identity_id)
  # with target_media_id NULL — the post-level reaction is the one
  # the bell was rung for.
  defp stream_reaction_type(%Notification{
         type: "reaction",
         target_type: "post",
         target_id: post_id,
         actor_id: actor_id
       })
       when is_binary(post_id) and is_binary(actor_id) do
    import Ecto.Query

    Hybridsocial.Social.Reaction
    |> where(
      [r],
      r.post_id == ^post_id and r.identity_id == ^actor_id and is_nil(r.target_media_id)
    )
    |> select([r], r.type)
    |> Repo.one()
  end

  defp stream_reaction_type(_), do: nil

  def list_notifications(identity_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    max_id = Keyword.get(opts, :max_id)
    types = Keyword.get(opts, :types)
    exclude_types = Keyword.get(opts, :exclude_types)

    Notification
    |> where([n], n.recipient_id == ^identity_id)
    |> filter_max_id(max_id)
    |> filter_types(types)
    |> filter_exclude_types(exclude_types)
    # `id DESC` is the explicit tie-breaker for notifications inserted
    # in the same instant; without it the row-tuple cursor below
    # couldn't deterministically pick the next-page boundary.
    |> order_by([n], desc: n.inserted_at, desc: n.id)
    |> limit(^limit)
    |> preload(:actor)
    |> Repo.all()
  end

  def get_notification(id, identity_id) do
    Notification
    |> where([n], n.id == ^id and n.recipient_id == ^identity_id)
    |> preload(:actor)
    |> Repo.one()
  end

  def mark_read(id, identity_id) do
    case get_notification(id, identity_id) do
      nil ->
        {:error, :not_found}

      notification ->
        notification
        |> Ecto.Changeset.change(read: true)
        |> Repo.update()
    end
  end

  def mark_all_read(identity_id) do
    Notification
    |> where([n], n.recipient_id == ^identity_id and n.read == false)
    |> Repo.update_all(set: [read: true, updated_at: DateTime.utc_now()])

    :ok
  end

  def unread_count(identity_id) do
    Notification
    |> where([n], n.recipient_id == ^identity_id and n.read == false)
    |> Repo.aggregate(:count, :id)
  end

  def clear_notifications(identity_id) do
    mark_all_read(identity_id)
  end

  def dismiss_notification(id, identity_id) do
    case get_notification(id, identity_id) do
      nil ->
        {:error, :not_found}

      notification ->
        Repo.delete(notification)
    end
  end

  # ---------------------------------------------------------------------------
  # Preferences
  # ---------------------------------------------------------------------------

  def get_preferences(identity_id) do
    Preference
    |> where([p], p.identity_id == ^identity_id)
    |> Repo.all()
    |> Enum.reduce(%{}, fn pref, acc ->
      Map.put(acc, pref.type, %{
        email: pref.email,
        push: pref.push,
        in_app: pref.in_app
      })
    end)
  end

  def update_preference(identity_id, type, attrs) do
    case Repo.get_by(Preference, identity_id: identity_id, type: type) do
      nil ->
        %Preference{}
        |> Preference.changeset(
          Map.merge(stringify_keys(attrs), %{"identity_id" => identity_id, "type" => type})
        )
        |> Repo.insert()

      preference ->
        preference
        |> Preference.changeset(stringify_keys(attrs))
        |> Repo.update()
    end
  end

  def should_notify?(identity_id, type, channel) when channel in [:email, :push, :in_app] do
    case Repo.get_by(Preference, identity_id: identity_id, type: type) do
      nil ->
        # Default values: email=false, push=true, in_app=true
        channel != :email

      preference ->
        Map.get(preference, channel)
    end
  end

  # For channels not stored in preferences (e.g. :sms, :noop), default to true.
  def should_notify?(_identity_id, _type, _channel), do: true

  @doc """
  Whether this identity wants email for `type`, using `default` when they haven't
  set a preference. A stored preference always wins, so it can opt out of an
  email that's on by default.
  """
  def email_enabled?(identity_id, type, default) when is_boolean(default) do
    case Repo.get_by(Preference, identity_id: identity_id, type: type) do
      nil -> default
      preference -> preference.email
    end
  end

  # ---------------------------------------------------------------------------
  # Convenience functions
  # ---------------------------------------------------------------------------

  def notify_follow(follower_id, followee_id) do
    create_notification(%{
      recipient_id: followee_id,
      actor_id: follower_id,
      type: "follow"
    })
  end

  def notify_reaction(actor_id, post) do
    create_notification(%{
      recipient_id: post.identity_id,
      actor_id: actor_id,
      type: "reaction",
      target_type: "post",
      target_id: post.id
    })
  end

  def notify_boost(actor_id, post) do
    create_notification(%{
      recipient_id: post.identity_id,
      actor_id: actor_id,
      type: "boost",
      target_type: "post",
      target_id: post.id
    })
  end

  def notify_reply(actor_id, _post, parent_post) do
    create_notification(%{
      recipient_id: parent_post.identity_id,
      actor_id: actor_id,
      type: "reply",
      target_type: "post",
      target_id: parent_post.id
    })
  end

  def notify_mention(actor_id, post, mentioned_ids) do
    Enum.each(mentioned_ids, fn mentioned_id ->
      create_notification(%{
        recipient_id: mentioned_id,
        actor_id: actor_id,
        type: "mention",
        target_type: "post",
        target_id: post.id
      })
    end)
  end

  def notify_poll_ended(poll) do
    # Notify the poll creator
    create_notification(%{
      recipient_id: poll.identity_id,
      actor_id: poll.identity_id,
      type: "poll_ended",
      target_type: "post",
      target_id: poll.post_id
    })

    # Notify voters if voter_ids is available
    voter_ids = Map.get(poll, :voter_ids, [])

    Enum.each(voter_ids, fn voter_id ->
      create_notification(%{
        recipient_id: voter_id,
        actor_id: poll.identity_id,
        type: "poll_ended",
        target_type: "post",
        target_id: poll.post_id
      })
    end)
  end

  def notify_group_invite(invite) do
    create_notification(%{
      recipient_id: invite.invited_id,
      actor_id: invite.invited_by,
      type: "group_invite",
      target_type: "group",
      target_id: invite.group_id
    })
  end

  # A new join request fans out to every group moderator/admin/owner. The
  # applicant is the actor; create_notification skips a recipient that equals
  # the actor, so a moderator applying to their own group won't self-notify.
  def notify_group_application(application, recipient_ids) do
    Enum.each(recipient_ids, fn recipient_id ->
      create_notification(%{
        recipient_id: recipient_id,
        actor_id: application.identity_id,
        type: "group_application",
        target_type: "group",
        target_id: application.group_id
      })
    end)
  end

  def notify_page_invite(invite) do
    create_notification(%{
      recipient_id: invite.invited_id,
      actor_id: invite.invited_by,
      type: "page_invite",
      target_type: "page",
      target_id: invite.page_id
    })
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp filter_max_id(query, nil), do: query

  # Notifications order by inserted_at DESC, so a `n.id < max_id` UUID
  # compare against that ordering returns an arbitrary slice and the
  # list freezes after the first page (the symptom: scroll loads page
  # one, then never advances). Look up the boundary row's inserted_at
  # first, then row-tuple compare on the same expression as the ORDER
  # BY. Falls through to no-cursor when the cursor doesn't resolve
  # (stale client, deleted notification) — never emit an empty page
  # just because the cursor is unrecognised.
  defp filter_max_id(query, max_id) when is_binary(max_id) do
    case Repo.one(
           from n in Notification,
             where: n.id == ^max_id,
             select: {n.inserted_at, n.id}
         ) do
      nil ->
        query

      {ia, id} ->
        where(
          query,
          [n],
          fragment("(?, ?) < (?, ?)", n.inserted_at, n.id, ^ia, type(^id, Ecto.UUID))
        )
    end
  end

  defp filter_max_id(query, _), do: query

  defp filter_types(query, nil), do: query
  defp filter_types(query, []), do: query

  defp filter_types(query, types) do
    where(query, [n], n.type in ^types)
  end

  defp filter_exclude_types(query, nil), do: query
  defp filter_exclude_types(query, []), do: query

  defp filter_exclude_types(query, exclude_types) do
    where(query, [n], n.type not in ^exclude_types)
  end

  defp maybe_deliver(notification, attrs, actor_id) do
    recipient_id = attrs[:recipient_id] || attrs["recipient_id"]
    type = attrs[:type] || attrs["type"]

    actor = Repo.get(Hybridsocial.Accounts.Identity, actor_id)
    actor_name = if actor, do: actor.display_name || actor.handle, else: "Someone"

    payload = %{
      title: push_title(type, actor_name),
      body: push_body(type),
      tag: "notification-#{notification.id}",
      data: %{
        type: type,
        target_type: attrs[:target_type] || attrs["target_type"],
        target_id: attrs[:target_id] || attrs["target_id"],
        url: "/notifications"
      }
    }

    for channel <- Hybridsocial.Notifications.DeliveryResolver.enabled_channels() do
      channel_atom = channel.channel_name()

      if should_notify?(recipient_id, type, channel_atom) do
        Task.start(fn -> channel.deliver(recipient_id, payload, %{}) end)
      end
    end
  end

  defp push_title(type, actor_name) do
    case type do
      "follow" -> "#{actor_name} followed you"
      "follow_request" -> "#{actor_name} requested to follow you"
      "reaction" -> "#{actor_name} reacted to your post"
      "boost" -> "#{actor_name} boosted your post"
      "quote" -> "#{actor_name} quoted your post"
      "reply" -> "#{actor_name} replied to your post"
      "mention" -> "#{actor_name} mentioned you"
      "poll_ended" -> "A poll has ended"
      "group_invite" -> "#{actor_name} invited you to a group"
      "group_application" -> "New group membership application"
      "page_invite" -> "#{actor_name} invited you to manage a page"
      _ -> push_title_staff(type)
    end
  end

  # Staff/moderation-facing notification titles, split out so the main lookup
  # stays under the cyclomatic-complexity limit as new types are added.
  defp push_title_staff(type) do
    case type do
      "report" -> "New report filed"
      "admin" -> "Admin notification"
      "moderation_takedown" -> "Your content was removed"
      _ -> "New notification"
    end
  end

  defp push_body(type) do
    case type do
      "follow" ->
        "You have a new follower"

      "follow_request" ->
        "You have a new follow request"

      "reaction" ->
        "Someone reacted to your post"

      "boost" ->
        "Your post was boosted"

      "quote" ->
        "Your post was quoted"

      "reply" ->
        "You have a new reply"

      "mention" ->
        "You were mentioned in a post"

      "poll_ended" ->
        "A poll you participated in has ended"

      "group_invite" ->
        "You have been invited to join a group"

      "group_application" ->
        "Someone applied to join your group"

      "page_invite" ->
        "You have been invited to manage a page"

      _ ->
        push_body_staff(type)
    end
  end

  # Staff/moderation-facing notification bodies (see push_title_staff/1).
  defp push_body_staff(type) do
    case type do
      "report" ->
        "A new report requires attention"

      "admin" ->
        "You have an admin notification"

      "moderation_takedown" ->
        "A moderator removed your content, open to see why and how to appeal"

      _ ->
        "You have a new notification"
    end
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
end
