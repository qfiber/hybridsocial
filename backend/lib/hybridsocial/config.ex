defmodule Hybridsocial.Config do
  @moduledoc """
  Public API for accessing instance configuration settings.

  Settings are stored in the database and cached in ETS for fast reads.
  """

  alias Hybridsocial.Config.Store

  @doc "Get a setting value by key."
  defdelegate get(key), to: Store

  @doc "Get a setting value by key with a default."
  defdelegate get(key, default), to: Store

  @doc "Set a setting value (writes to DB and updates ETS cache)."
  defdelegate set(key, value), to: Store

  @doc "Delete a setting so readers fall back to their defaults."
  defdelegate delete(key), to: Store

  @doc "Get all settings as a map."
  defdelegate all(), to: Store

  @doc "Get all settings for a category."
  defdelegate all(category), to: Store

  # Convenience functions

  @doc "Get the instance name."
  def instance_name, do: get("instance_name", "HybridSocial")

  @doc "Get the instance description."
  def instance_description, do: get("instance_description", "")

  @doc "Get the max post length for free users."
  def max_post_length_free, do: get("max_post_length_free", 5000)

  @doc "Get the max post length for premium users."
  def max_post_length_premium, do: get("max_post_length_premium", 10_000)

  @doc "Check if registration is open."
  def registration_open?, do: get("registration_mode", "open") == "open"

  @doc "Check if federation is enabled."
  def federation_enabled?, do: get("federation_enabled", true)

  @doc "Check if email confirmation is required."
  def require_email_confirmation?, do: get("require_email_confirmation", true)

  # 1200 authenticated / 240 anonymous per minute. Previous defaults
  # (300 / 60) caught legitimate SPA traffic when a single page load
  # does ~15 API calls (feed, notifications, me, streaming poll,
  # instance, tier). Auth-sensitive endpoints (login, register, 2FA)
  # still have their own stricter per-endpoint caps in
  # `Plugs.RateLimiter.get_limit/1`.
  @doc "Get the rate limit for authenticated users."
  def rate_limit_authenticated, do: get("rate_limit_authenticated", 1200)

  @doc "Get the rate limit for anonymous users."
  def rate_limit_anonymous, do: get("rate_limit_anonymous", 240)

  # ActivityPub federation traffic (actor JSON, webfinger, inbox, dereferenceable
  # objects) needs a much higher ceiling than browser-anonymous: a single
  # remote Mastodon instance may fetch our actor + 5 objects + outbox sample
  # within seconds while verifying a signed activity. 240/min per IP starves
  # legitimate fediverse peers and produced "Unable to fetch key JSON" errors
  # on outgoing Follows. Per-IP key keeps some DoS protection.
  @doc "Get the rate limit for federation endpoints (per IP, per minute)."
  def rate_limit_federation, do: get("rate_limit_federation", 1800)

  # --- Subaccount limits ---

  @doc "Max bot subaccounts per user."
  def max_bots_per_user, do: get("max_bots_per_user", 4)

  @doc "Max organization (page) subaccounts per user."
  def max_organizations_per_user, do: get("max_organizations_per_user", 2)

  @doc "Max group subaccounts per user."
  def max_groups_per_user, do: get("max_groups_per_user", 4)
end
