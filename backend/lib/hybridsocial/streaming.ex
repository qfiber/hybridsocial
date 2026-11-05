defmodule Hybridsocial.Streaming do
  @moduledoc """
  Streaming context. Broadcasts events to both local PubSub and NATS
  for multi-node real-time updates.
  """

  alias Phoenix.PubSub

  @pubsub Hybridsocial.PubSub

  def broadcast_post(post) do
    event = %{event: "update", payload: post}
    visibility = post[:visibility] || post["visibility"]

    tags = post[:tags] || post["tags"] || []
    hidden? = Hybridsocial.Moderation.any_hashtag_hidden?(tag_names(tags))

    # A post carrying a hidden hashtag still reaches its author and followers,
    # but must not arrive on public streams after being filtered from the feeds.
    unless hidden?, do: maybe_broadcast_public(event, visibility)
    maybe_broadcast_author_and_followers(event, author_id_from(post), visibility)
    maybe_broadcast_group(event, post[:group_id] || post["group_id"])
    unless hidden?, do: broadcast_tags(event, tags)

    :ok
  end

  defp tag_names(tags) when is_list(tags) do
    tags
    |> Enum.map(fn tag -> if is_map(tag), do: tag["name"] || tag[:name], else: tag end)
    |> Enum.filter(&is_binary/1)
  end

  defp tag_names(_), do: []

  # Public + unlisted land on the explore/public stream; followers
  # and direct posts do not.
  defp maybe_broadcast_public(event, visibility) when visibility in ["public", "unlisted"] do
    local_broadcast("timeline:public", event)
    nats_publish("events.timeline.public", event)
  end

  defp maybe_broadcast_public(_event, _visibility), do: :ok

  # Author id may arrive flat (account_id) or nested (account.id).
  # PostSerializer nests; older call sites passed a flat struct.
  defp author_id_from(post) do
    post[:account_id] || post["account_id"] ||
      get_in(post, [:account, :id]) || get_in(post, ["account", "id"]) ||
      post[:identity_id] || post["identity_id"]
  end

  defp maybe_broadcast_author_and_followers(_event, nil, _visibility), do: :ok

  defp maybe_broadcast_author_and_followers(event, author_id, visibility) do
    # Author's own `user:<id>` topic — they see their own post in
    # their home stream.
    local_broadcast("user:#{author_id}", event)
    nats_publish("events.user.#{author_id}", event)

    # Home-timeline fan-out: broadcast to every accepted follower
    # so their `user:<follower_id>` SSE stream picks the post up
    # and shows the "N new posts" banner. Skip direct posts (they
    # reach the recipient via broadcast_dm / the direct stream).
    if visibility in ["public", "unlisted", "followers"] do
      fan_out_to_followers(author_id, event)
    end
  end

  defp maybe_broadcast_group(_event, nil), do: :ok

  defp maybe_broadcast_group(event, group_id) do
    local_broadcast("group:#{group_id}", event)
    nats_publish("events.group.#{group_id}", event)
  end

  defp broadcast_tags(event, tags) when is_list(tags) do
    Enum.each(tags, fn tag ->
      tag_name = if is_map(tag), do: tag["name"] || tag[:name], else: tag
      local_broadcast("hashtag:#{tag_name}", event)
      nats_publish("events.hashtag.#{tag_name}", event)
    end)
  end

  defp broadcast_tags(_event, _), do: :ok

  # Publishes the post event to every accepted follower's personal
  # user:<id> topic. Runs inline — O(F) local PubSub sends per new
  # post, one NATS publish to a topic the bridge will fan out on
  # other nodes. Safe to call from a hot path since PubSub.broadcast
  # is just an ETS lookup + message send.
  defp fan_out_to_followers(author_id, event) do
    import Ecto.Query

    follower_ids =
      from(f in Hybridsocial.Social.Follow,
        where: f.followee_id == ^author_id and f.status == :accepted,
        select: f.follower_id
      )
      |> Hybridsocial.Repo.all()

    Enum.each(follower_ids, fn follower_id ->
      local_broadcast("user:#{follower_id}", event)
      nats_publish("events.user.#{follower_id}", event)
    end)
  end

  def broadcast_notification(notification) do
    user_id = notification[:account_id] || notification["account_id"]

    if user_id do
      event = %{event: "notification", payload: notification}
      local_broadcast("user:#{user_id}", event)
      nats_publish("events.user.#{user_id}", event)
    end

    :ok
  end

  def broadcast_delete(post_id) do
    event = %{event: "delete", payload: post_id}
    local_broadcast("timeline:public", event)
    nats_publish("events.timeline.public", event)
    :ok
  end

  def broadcast_dm(conversation_id, message) do
    event = %{event: "conversation", payload: message}
    local_broadcast("direct:#{conversation_id}", event)
    nats_publish("events.direct.#{conversation_id}", event)
    :ok
  end

  # Local PubSub (same node)
  defp local_broadcast(topic, event) do
    PubSub.broadcast(@pubsub, topic, event)
  end

  # NATS (cross-node) — fire and forget, non-blocking
  defp nats_publish(subject, event) do
    Hybridsocial.Nats.publish(subject, event)
  rescue
    _ -> :ok
  end
end
