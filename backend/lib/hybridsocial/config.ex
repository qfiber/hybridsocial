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

  @doc "Get the rate limit for authenticated users."
  def rate_limit_authenticated, do: get("rate_limit_authenticated", 300)

  @doc "Get the rate limit for anonymous users."
  def rate_limit_anonymous, do: get("rate_limit_anonymous", 60)
end
