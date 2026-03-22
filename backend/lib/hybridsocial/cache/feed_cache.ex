defmodule Hybridsocial.Cache.FeedCache do
  @moduledoc "Feed-specific caching backed by Valkey."

  alias Hybridsocial.Cache

  def get_home_timeline(identity_id) do
    Cache.get("feed:home:#{identity_id}")
  end

  def set_home_timeline(identity_id, posts, ttl \\ 60) do
    Cache.set("feed:home:#{identity_id}", posts, ttl)
  end

  def get_public_timeline do
    Cache.get("feed:public")
  end

  def set_public_timeline(posts, ttl \\ 30) do
    Cache.set("feed:public", posts, ttl)
  end

  def invalidate_home_timeline(identity_id) do
    Cache.delete("feed:home:#{identity_id}")
  end

  def invalidate_public_timeline do
    Cache.delete("feed:public")
  end

  def invalidate_group_timeline(group_id) do
    Cache.delete("feed:group:#{group_id}")
  end
end
