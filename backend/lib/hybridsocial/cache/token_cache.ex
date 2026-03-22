defmodule Hybridsocial.Cache.TokenCache do
  @moduledoc "Identity/token caching to avoid DB lookups on every request."

  alias Hybridsocial.Cache

  def cache_identity(identity_id, identity_data, ttl \\ 300) do
    Cache.set("identity:#{identity_id}", identity_data, ttl)
  end

  def get_cached_identity(identity_id) do
    Cache.get("identity:#{identity_id}")
  end

  def invalidate_identity(identity_id) do
    Cache.delete("identity:#{identity_id}")
  end
end
