defmodule Hybridsocial.Streaming do
  @moduledoc """
  Streaming context. Broadcasts events to both local PubSub and NATS
  for multi-node real-time updates.
  """

  alias Phoenix.PubSub

  @pubsub Hybridsocial.PubSub

  def broadcast_post(post) do
    event = %{event: "update", payload: post}

    if post[:visibility] == "public" or post["visibility"] == "public" do
      local_broadcast("timeline:public", event)
      nats_publish("events.timeline.public", event)
    end

    author_id = post[:account_id] || post["account_id"]

    if author_id do
      local_broadcast("user:#{author_id}", event)
      nats_publish("events.user.#{author_id}", event)
    end

    group_id = post[:group_id] || post["group_id"]

    if group_id do
      local_broadcast("group:#{group_id}", event)
      nats_publish("events.group.#{group_id}", event)
    end

    tags = post[:tags] || post["tags"] || []

    Enum.each(tags, fn tag ->
      tag_name = if is_map(tag), do: tag["name"] || tag[:name], else: tag
      local_broadcast("hashtag:#{tag_name}", event)
      nats_publish("events.hashtag.#{tag_name}", event)
    end)

    :ok
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
