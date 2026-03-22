defmodule Hybridsocial.Cache.FeedCacheTest do
  use ExUnit.Case, async: false

  alias Hybridsocial.Cache.FeedCache

  setup do
    Redix.command!(:"valkey_0", ["FLUSHDB"])
    :ok
  end

  describe "home timeline cache" do
    test "returns nil when not cached" do
      assert FeedCache.get_home_timeline("identity-1") == nil
    end

    test "caches and retrieves home timeline" do
      posts = [
        %{"id" => "post-1", "content" => "Hello"},
        %{"id" => "post-2", "content" => "World"}
      ]

      FeedCache.set_home_timeline("identity-1", posts)
      assert FeedCache.get_home_timeline("identity-1") == posts
    end

    test "invalidates home timeline" do
      FeedCache.set_home_timeline("identity-1", [%{"id" => "post-1"}])
      FeedCache.invalidate_home_timeline("identity-1")
      assert FeedCache.get_home_timeline("identity-1") == nil
    end

    test "caches with custom TTL" do
      FeedCache.set_home_timeline("identity-1", [%{"id" => "post-1"}], 1)
      assert FeedCache.get_home_timeline("identity-1") != nil
      Process.sleep(1100)
      assert FeedCache.get_home_timeline("identity-1") == nil
    end
  end

  describe "public timeline cache" do
    test "returns nil when not cached" do
      assert FeedCache.get_public_timeline() == nil
    end

    test "caches and retrieves public timeline" do
      posts = [%{"id" => "post-1", "content" => "Public post"}]

      FeedCache.set_public_timeline(posts)
      assert FeedCache.get_public_timeline() == posts
    end

    test "invalidates public timeline" do
      FeedCache.set_public_timeline([%{"id" => "post-1"}])
      FeedCache.invalidate_public_timeline()
      assert FeedCache.get_public_timeline() == nil
    end
  end

  describe "group timeline cache" do
    test "invalidates group timeline" do
      # Set via the base cache directly since no get_group_timeline is defined
      Hybridsocial.Cache.set("feed:group:group-1", [%{"id" => "post-1"}])
      FeedCache.invalidate_group_timeline("group-1")
      assert Hybridsocial.Cache.get("feed:group:group-1") == nil
    end
  end
end
