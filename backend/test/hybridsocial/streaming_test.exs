defmodule Hybridsocial.StreamingTest do
  use Hybridsocial.DataCase, async: true

  alias Hybridsocial.Streaming

  describe "broadcast_post/1" do
    test "broadcasts public post to public timeline" do
      Phoenix.PubSub.subscribe(Hybridsocial.PubSub, "timeline:public")

      post = %{
        id: "post-1",
        content: "Hello world",
        visibility: "public",
        account_id: "user-1",
        tags: []
      }

      assert :ok = Streaming.broadcast_post(post)
      assert_receive %{event: "update", payload: ^post}
    end

    test "broadcasts post to author's user topic" do
      Phoenix.PubSub.subscribe(Hybridsocial.PubSub, "user:user-1")

      post = %{
        id: "post-2",
        content: "Hello",
        visibility: "public",
        account_id: "user-1",
        tags: []
      }

      assert :ok = Streaming.broadcast_post(post)
      assert_receive %{event: "update", payload: ^post}
    end

    test "broadcasts post to group topic" do
      Phoenix.PubSub.subscribe(Hybridsocial.PubSub, "group:group-1")

      post = %{
        id: "post-3",
        content: "Group post",
        visibility: "public",
        account_id: "user-1",
        group_id: "group-1",
        tags: []
      }

      assert :ok = Streaming.broadcast_post(post)
      assert_receive %{event: "update", payload: ^post}
    end

    test "broadcasts post to hashtag topics" do
      Phoenix.PubSub.subscribe(Hybridsocial.PubSub, "hashtag:elixir")

      post = %{
        id: "post-4",
        content: "Tagged post",
        visibility: "public",
        account_id: "user-1",
        tags: ["elixir"]
      }

      assert :ok = Streaming.broadcast_post(post)
      assert_receive %{event: "update", payload: ^post}
    end

    test "does not broadcast private posts to public timeline" do
      Phoenix.PubSub.subscribe(Hybridsocial.PubSub, "timeline:public")

      post = %{
        id: "post-5",
        content: "Private post",
        visibility: "private",
        account_id: "user-1",
        tags: []
      }

      assert :ok = Streaming.broadcast_post(post)
      refute_receive %{event: "update", payload: _}
    end
  end

  describe "broadcast_notification/1" do
    test "broadcasts notification to user topic" do
      Phoenix.PubSub.subscribe(Hybridsocial.PubSub, "user:user-1")

      notification = %{
        id: "notif-1",
        type: "follow",
        account_id: "user-1"
      }

      assert :ok = Streaming.broadcast_notification(notification)
      assert_receive %{event: "notification", payload: ^notification}
    end
  end

  describe "broadcast_delete/1" do
    test "broadcasts delete event to public timeline" do
      Phoenix.PubSub.subscribe(Hybridsocial.PubSub, "timeline:public")

      assert :ok = Streaming.broadcast_delete("post-1")
      assert_receive %{event: "delete", payload: "post-1"}
    end
  end

  describe "broadcast_dm/2" do
    test "broadcasts direct message to conversation topic" do
      Phoenix.PubSub.subscribe(Hybridsocial.PubSub, "direct:conv-1")

      message = %{id: "msg-1", content: "Hello DM"}

      assert :ok = Streaming.broadcast_dm("conv-1", message)
      assert_receive %{event: "conversation", payload: ^message}
    end
  end
end
