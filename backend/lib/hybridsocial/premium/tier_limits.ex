defmodule Hybridsocial.Premium.TierLimits do
  @moduledoc """
  Central module for resolving tiered verification limits.
  Reads all values from Config (ETS-cached) with hardcoded defaults as fallback.
  When the tier system is disabled, everyone gets L3 (verified_pro) limits.
  """

  alias Hybridsocial.Config

  @tiers ~w(free verified_starter verified_creator verified_pro)

  @defaults %{
    "free" => %{
      char_limit: 800,
      markdown: "none",
      video_resolution: 720,
      video_duration: 90,
      image_size_mb: 1,
      video_size_mb: 15,
      media_per_post: 2,
      poll_options: 2,
      edit_window: 900,
      pinned_posts: 1,
      profile_fields: 0,
      scheduled_posts: false,
      custom_emoji: false,
      follows_limit: 100
    },
    "verified_starter" => %{
      char_limit: 1200,
      markdown: "basic",
      video_resolution: 720,
      video_duration: 200,
      image_size_mb: 3,
      video_size_mb: 20,
      media_per_post: 4,
      poll_options: 4,
      edit_window: 1800,
      pinned_posts: 2,
      profile_fields: 2,
      scheduled_posts: false,
      custom_emoji: false,
      follows_limit: 0
    },
    "verified_creator" => %{
      char_limit: 3000,
      markdown: "full",
      video_resolution: 1080,
      video_duration: 300,
      image_size_mb: 5,
      video_size_mb: 25,
      media_per_post: 6,
      poll_options: 6,
      edit_window: 86400,
      pinned_posts: 5,
      profile_fields: 5,
      scheduled_posts: true,
      custom_emoji: false,
      follows_limit: 0
    },
    "verified_pro" => %{
      char_limit: 5000,
      markdown: "full_embeds",
      video_resolution: 1080,
      video_duration: 600,
      image_size_mb: 10,
      video_size_mb: 40,
      media_per_post: 10,
      poll_options: 10,
      edit_window: 0,
      pinned_posts: 10,
      profile_fields: 10,
      scheduled_posts: true,
      custom_emoji: true,
      follows_limit: 0
    }
  }

  @limit_keys Map.keys(@defaults["free"])

  def tiers, do: @tiers
  def limit_keys, do: @limit_keys
  def defaults, do: @defaults

  @doc "Whether the tiered system is enabled."
  def enabled? do
    Config.get("tiers_enabled", false) == true
  end

  @doc "Whether payment is configured (advisory flag)."
  def payment_configured? do
    Config.get("tiers_payment_configured", false) == true
  end

  @doc "Get the effective tier for an identity."
  def get_tier(identity) do
    if enabled?() do
      identity.verification_tier || "free"
    else
      # When disabled, everyone gets max limits
      "verified_pro"
    end
  end

  @doc "Get all limits for an identity as a map."
  def limits_for(identity) do
    tier = get_tier(identity)
    limits_for_tier(tier)
  end

  @doc "Get all limits for a specific tier."
  def limits_for_tier(tier) when tier in @tiers do
    tier_defaults = @defaults[tier]

    Map.new(tier_defaults, fn {key, default} ->
      config_key = "tier_#{tier}_#{key}"
      {key, Config.get(config_key, default)}
    end)
  end

  def limits_for_tier(_), do: limits_for_tier("free")

  @doc "Get a single limit value for an identity."
  def limit(identity, key) when is_atom(key) do
    tier = get_tier(identity)
    config_key = "tier_#{tier}_#{key}"
    Config.get(config_key, @defaults[tier][key])
  end

  @doc "Get all tier configs (for admin UI / comparison display)."
  def all_tier_configs do
    Map.new(@tiers, fn tier ->
      {tier, limits_for_tier(tier)}
    end)
  end
end
