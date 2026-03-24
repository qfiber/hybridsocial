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
            maybe_send_push(notification, attrs, actor_id)
            {:ok, notification}

          error ->
            error
        end
    end
  end

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
    |> order_by([n], desc: n.inserted_at)
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
      actor_id: invite.inviter_id,
      type: "group_invite",
      target_type: "group",
      target_id: invite.group_id
    })
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp filter_max_id(query, nil), do: query

  defp filter_max_id(query, max_id) do
    where(query, [n], n.id < ^max_id)
  end

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

  defp maybe_send_push(notification, attrs, actor_id) do
    recipient_id = attrs[:recipient_id] || attrs["recipient_id"]
    type = attrs[:type] || attrs["type"]

    if should_notify?(recipient_id, type, :push) do
      Task.start(fn ->
        actor = Repo.get(Hybridsocial.Accounts.Identity, actor_id)
        actor_name = if actor, do: actor.display_name || actor.handle, else: "Someone"

        Hybridsocial.Push.Delivery.send_to_user(recipient_id, %{
          title: push_title(type, actor_name),
          body: push_body(type),
          tag: "notification-#{notification.id}",
          data: %{
            type: type,
            target_type: attrs[:target_type] || attrs["target_type"],
            target_id: attrs[:target_id] || attrs["target_id"],
            url: "/notifications"
          }
        })
      end)
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
      "report" -> "New report filed"
      "admin" -> "Admin notification"
      _ -> "New notification"
    end
  end

  defp push_body(type) do
    case type do
      "follow" -> "You have a new follower"
      "follow_request" -> "You have a new follow request"
      "reaction" -> "Someone reacted to your post"
      "boost" -> "Your post was boosted"
      "quote" -> "Your post was quoted"
      "reply" -> "You have a new reply"
      "mention" -> "You were mentioned in a post"
      "poll_ended" -> "A poll you participated in has ended"
      "group_invite" -> "You have been invited to join a group"
      "group_application" -> "Someone applied to join your group"
      "report" -> "A new report requires attention"
      "admin" -> "You have an admin notification"
      _ -> "You have a new notification"
    end
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
end
