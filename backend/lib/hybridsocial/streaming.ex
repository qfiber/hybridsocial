defmodule Hybridsocial.Streaming do
  @moduledoc """
  Streaming context. Broadcasts events to PubSub topics for real-time updates.
  """

  alias Phoenix.PubSub

  @pubsub Hybridsocial.PubSub

  @doc """
  Broadcasts a new or updated post to relevant PubSub topics.
  Publishes to: public timeline, author's followers, groups, and hashtags.
  """
  def broadcast_post(post) do
    event = %{event: "update", payload: post}

    # Public timeline (only for public posts)
    if post[:visibility] == "public" or post["visibility"] == "public" do
      PubSub.broadcast(@pubsub, "timeline:public", event)
    end

    # Author's followers
    author_id = post[:account_id] || post["account_id"]

    if author_id do
      PubSub.broadcast(@pubsub, "user:#{author_id}", event)
    end

    # Group timeline
    group_id = post[:group_id] || post["group_id"]

    if group_id do
      PubSub.broadcast(@pubsub, "group:#{group_id}", event)
    end

    # Hashtag timelines
    tags = post[:tags] || post["tags"] || []

    Enum.each(tags, fn tag ->
      tag_name = if is_map(tag), do: tag["name"] || tag[:name], else: tag
      PubSub.broadcast(@pubsub, "hashtag:#{tag_name}", event)
    end)

    :ok
  end

  @doc """
  Broadcasts a notification to a user's stream.
  """
  def broadcast_notification(notification) do
    user_id = notification[:account_id] || notification["account_id"]

    if user_id do
      PubSub.broadcast(
        @pubsub,
        "user:#{user_id}",
        %{event: "notification", payload: notification}
      )
    end

    :ok
  end

  @doc """
  Broadcasts a delete event for a post.
  """
  def broadcast_delete(post_id) do
    PubSub.broadcast(
      @pubsub,
      "timeline:public",
      %{event: "delete", payload: post_id}
    )

    :ok
  end

  @doc """
  Broadcasts a direct message to conversation participants.
  """
  def broadcast_dm(conversation_id, message) do
    PubSub.broadcast(
      @pubsub,
      "direct:#{conversation_id}",
      %{event: "conversation", payload: message}
    )

    :ok
  end
end
