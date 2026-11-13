defmodule Hybridsocial.Config.Registry do
  @moduledoc """
  Declares every runtime setting the admin settings API may read and write.

  `Config` values are stored untyped, so before this registry existed the
  `PUT /api/v1/admin/settings` endpoint wrote any key with whatever JSON type
  the client sent. Each entry here fixes a key's type, bounds and admin group,
  so writes are allowlisted and cast before they reach the database, and the
  admin panel renders its settings pages from `schema/0`.

  Entry fields:

    * `:type` - `:string`, `:integer`, `:number`, `:boolean`, `:string_list`,
      or `{:enum, values}`
    * `:group` / `:section` - where the setting lives in the admin panel; each
      group is guarded by its own permission (`permission_for/1`)
    * `:default` - the value readers fall back to when nothing is stored, shown
      in the UI. Resetting a setting deletes its row, so the reader's own
      default applies even if this one drifts
    * `:min` / `:max` - inclusive numeric bounds
    * `:max_length` - string length cap
    * `:unit` - display unit (`:seconds`, `:days`, `:bytes`, ...)
    * `:secret` - write-only: never returned by the API, redacted in the audit log
    * `:advanced` - an expert tunable, shown behind an "Advanced" disclosure
    * `:nullable` - an empty string is stored as `nil` (the reader's "unset")
    * `:multiline` - render as a textarea
    * `:visible_when` - `{key, value}`: only relevant while `key` equals `value`
    * `:page` - edited on a dedicated admin page instead of the generic one

  Keys that dedicated endpoints own entirely (theme, email transport,
  translation, rules, VAPID keys) are not listed here.
  """

  alias Hybridsocial.Premium.TierLimits

  @type entry :: %{required(:key) => String.t(), optional(atom()) => term()}

  # Group order is the order the admin panel lists them in.
  @groups [
    general: "settings.manage",
    branding: "theme.manage",
    access: "settings.access",
    posting: "settings.posting",
    media: "settings.media",
    discovery: "settings.discovery",
    federation: "federation.manage",
    moderation: "settings.moderation",
    rate_limits: "settings.rate_limits",
    monetization: "settings.monetization",
    integrations: "settings.integrations",
    retention: "settings.retention"
  ]

  @secret [secret: true, max_length: 2048]
  @url [max_length: 2048]
  @adv [advanced: true]

  # {group, section, key, type, default, opts}
  @spec_rows [
    # --- General -------------------------------------------------------------
    {:general, :identity, "instance_name", :string, "HybridSocial", max_length: 100},
    {:general, :identity, "instance_short_description", :string, "", max_length: 500},
    {:general, :identity, "instance_description", :string, "", max_length: 5000, multiline: true},
    {:general, :identity, "instance_languages", :string_list, ["en"], []},
    {:general, :contact, "contact_email", :string, "", max_length: 254},
    {:general, :contact, "contact_account_handle", :string, nil, max_length: 100, nullable: true},
    {:general, :images, "instance_thumbnail", :string, nil, @url ++ [nullable: true]},
    {:general, :images, "instance_background_image", :string, nil, @url ++ [nullable: true]},
    {:general, :links, "source_url", :string, "https://github.com/qfiber/hybridsocial", @url},

    # --- Branding ------------------------------------------------------------
    {:branding, :apps, "app_banner_enabled", :boolean, false, []},
    {:branding, :apps, "app_ios_url", :string, "", @url},
    {:branding, :apps, "app_android_url", :string, "", @url},
    {:branding, :apps, "app_fdroid_url", :string, "", @url},
    {:branding, :email, "email_logo_url", :string, "", @url},

    # --- Sign-up & access ----------------------------------------------------
    {:access, :signup, "registration_mode", {:enum, ~w(open approval invite_only closed)}, "open",
     []},
    {:access, :signup, "require_email_confirmation", :boolean, true, []},
    {:access, :signup, "reserved_handles", :string_list, [], []},
    {:access, :bot_protection, "captcha_provider", {:enum, ~w(none turnstile hcaptcha recaptcha)},
     "none", []},
    {:access, :bot_protection, "turnstile_site_key", :string, "",
     max_length: 512, visible_when: {"captcha_provider", "turnstile"}},
    {:access, :bot_protection, "turnstile_secret_key", :string, "",
     @secret ++ [visible_when: {"captcha_provider", "turnstile"}]},
    {:access, :bot_protection, "hcaptcha_site_key", :string, "",
     max_length: 512, visible_when: {"captcha_provider", "hcaptcha"}},
    {:access, :bot_protection, "hcaptcha_secret_key", :string, "",
     @secret ++ [visible_when: {"captcha_provider", "hcaptcha"}]},
    {:access, :bot_protection, "recaptcha_site_key", :string, "",
     max_length: 512, visible_when: {"captcha_provider", "recaptcha"}},
    {:access, :bot_protection, "recaptcha_secret_key", :string, "",
     @secret ++ [visible_when: {"captcha_provider", "recaptcha"}]},
    {:access, :bot_protection, "recaptcha_min_score", :number, 0.5,
     min: 0, max: 1, visible_when: {"captcha_provider", "recaptcha"}},
    {:access, :bot_protection, "pow_enabled", :boolean, false, []},
    {:access, :bot_protection, "pow_difficulty", :integer, 16, min: 8, max: 24, advanced: true},
    {:access, :visibility, "public_timeline_access", {:enum, ~w(all local none)}, "all", []},
    {:access, :sessions, "password_reset_ttl_seconds", :integer, 3600,
     min: 300, max: 604_800, unit: :seconds, advanced: true},
    {:access, :sessions, "oauth_app_token_ttl_days", :integer, 60,
     min: 1, max: 3650, unit: :days, advanced: true},

    # --- Posting & accounts --------------------------------------------------
    {:posting, :posts, "max_post_length_free", :integer, 5000, min: 1, unit: :chars},
    {:posting, :posts, "max_post_length_premium", :integer, 10_000,
     min: 1, unit: :chars, advanced: true},
    {:posting, :posts, "max_media_per_post", :integer, 4, min: 0, max: 40},
    {:posting, :posts, "characters_reserved_per_url", :integer, 23,
     min: 0, max: 2048, unit: :chars, advanced: true},
    {:posting, :polls, "max_poll_options", :integer, 4, min: 2, max: 50},
    {:posting, :polls, "max_poll_option_chars", :integer, 200, min: 1, unit: :chars},
    {:posting, :polls, "min_poll_expiration", :integer, 300, min: 60, unit: :seconds},
    {:posting, :polls, "max_poll_expiration", :integer, 2_629_746, min: 60, unit: :seconds},
    {:posting, :timed_posts, "post_expiry_min_seconds", :integer, 300, min: 60, unit: :seconds},
    {:posting, :timed_posts, "post_expiry_max_seconds", :integer, 31_536_000,
     min: 60, unit: :seconds},
    {:posting, :timed_posts, "post_expiry_sweep_seconds", :integer, 60,
     min: 10, unit: :seconds, advanced: true},
    {:posting, :timed_posts, "post_expiry_batch_size", :integer, 500,
     min: 1, max: 10_000, advanced: true},
    {:posting, :profiles, "max_profile_fields", :integer, 5, min: 0, max: 50},
    {:posting, :profiles, "max_field_name_length", :integer, 512, min: 1, unit: :chars},
    {:posting, :profiles, "max_field_value_length", :integer, 2048, min: 1, unit: :chars},
    {:posting, :profiles, "max_featured_tags", :integer, 10, min: 0, max: 100},
    {:posting, :pins, "max_pinned_in_group", :integer, 3, min: 0, max: 50},
    {:posting, :pins, "max_pinned_on_page", :integer, 3, min: 0, max: 50},
    {:posting, :subaccounts, "max_bots_per_user", :integer, 4, min: 0, max: 100},
    {:posting, :subaccounts, "max_groups_per_user", :integer, 4, min: 0, max: 100},
    {:posting, :subaccounts, "max_organizations_per_user", :integer, 2, min: 0, max: 100},
    {:posting, :messages, "dm_edit_window_seconds", :integer, 300, min: 0, unit: :seconds},
    {:posting, :messages, "group_dm_max_participants", :integer, 25, min: 2, max: 500},
    {:posting, :trust, "trust_gate_links", :boolean, true, []},
    {:posting, :trust, "trust_gate_dms", :boolean, true, []},
    {:posting, :trust, "trust_sweep_interval_minutes", :integer, 60,
     min: 1, unit: :minutes, advanced: true},
    # 0 = unlimited. Edited on the Posting limits page.
    {:posting, :rate, "user_posts_per_minute", :integer, 6, min: 0, page: :posting_limits},
    {:posting, :rate, "user_posts_per_hour", :integer, 20, min: 0, page: :posting_limits},
    {:posting, :rate, "user_posts_per_day", :integer, 100, min: 0, page: :posting_limits},
    {:posting, :rate, "bot_posts_per_minute", :integer, 10, min: 0, page: :posting_limits},
    {:posting, :rate, "bot_posts_per_hour", :integer, 30, min: 0, page: :posting_limits},
    {:posting, :rate, "bot_posts_per_day", :integer, 0, min: 0, page: :posting_limits},

    # --- Media & storage -----------------------------------------------------
    {:media, :uploads, "max_image_size_mb", :integer, 10, min: 1, max: 1000, unit: :mb},
    {:media, :uploads, "max_video_size_mb", :integer, 100, min: 1, max: 10_000, unit: :mb},
    {:media, :uploads, "max_avatar_size", :integer, 2_000_000, min: 1, unit: :bytes},
    {:media, :uploads, "max_banner_size", :integer, 4_000_000, min: 1, unit: :bytes},
    {:media, :uploads, "max_background_size", :integer, 4_000_000, min: 1, unit: :bytes},
    {:media, :uploads, "max_upload_payload_bytes", :integer, 100_000_000,
     min: 1, unit: :bytes, advanced: true},
    {:media, :processing, "image_matrix_limit", :integer, 33_177_600,
     min: 1, unit: :pixels, advanced: true},
    {:media, :processing, "video_matrix_limit", :integer, 8_294_400,
     min: 1, unit: :pixels, advanced: true},
    {:media, :processing, "video_frame_rate_limit", :integer, 120,
     min: 1, max: 1000, unit: :fps, advanced: true},
    {:media, :processing, "streams_min_duration_seconds", :integer, 10, min: 0, unit: :seconds},
    {:media, :storage, "storage_backend", {:enum, ~w(local s3 r2)}, "local", @adv},
    {:media, :storage, "s3_bucket", :string, nil,
     max_length: 255, nullable: true, visible_when: {"storage_backend", "s3"}},
    {:media, :storage, "s3_endpoint", :string, nil,
     @url ++ [nullable: true, visible_when: {"storage_backend", "s3"}]},
    {:media, :storage, "s3_region", :string, nil,
     max_length: 64, nullable: true, visible_when: {"storage_backend", "s3"}},
    {:media, :storage, "r2_account_id", :string, nil,
     max_length: 255, nullable: true, visible_when: {"storage_backend", "r2"}},
    {:media, :storage, "r2_bucket", :string, nil,
     max_length: 255, nullable: true, visible_when: {"storage_backend", "r2"}},
    {:media, :storage, "r2_access_key", :string, nil,
     @secret ++ [visible_when: {"storage_backend", "r2"}]},
    {:media, :storage, "r2_secret_key", :string, nil,
     @secret ++ [visible_when: {"storage_backend", "r2"}]},
    {:media, :proxy, "media_proxy_enabled", :boolean, false, []},
    {:media, :proxy, "media_proxy_max_bytes", :integer, 100_000_000,
     min: 1, unit: :bytes, advanced: true},
    {:media, :proxy, "media_proxy_cache_enabled", :boolean, true, []},
    {:media, :proxy, "media_proxy_cache_ttl_days", :integer, 7, min: 1, unit: :days},
    {:media, :proxy, "media_proxy_cache_max_bytes", :integer, 5_368_709_120,
     min: 1, unit: :bytes, advanced: true},
    {:media, :antivirus, "clamav_enabled", :boolean, false, []},
    {:media, :antivirus, "clamav_host", :string, "clamav", max_length: 255},
    {:media, :antivirus, "clamav_port", :integer, 3310, min: 1, max: 65_535},
    {:media, :antivirus, "clamav_timeout_ms", :integer, 30_000,
     min: 100, unit: :milliseconds, advanced: true},
    {:media, :antivirus, "infected_upload_threshold", :integer, 5, min: 1},
    {:media, :antivirus, "infected_upload_window_seconds", :integer, 3600,
     min: 60, unit: :seconds, advanced: true},

    # --- Feeds & discovery ---------------------------------------------------
    {:discovery, :timelines, "default_timeline_algorithm",
     {:enum, ~w(chronological algorithmic trending)}, "chronological", []},
    {:discovery, :timelines, "feed_collapse_author_runs_after", :integer, 2, min: 0, max: 50},
    {:discovery, :timelines, "global_feed_prewarm_enabled", :boolean, true, @adv},
    {:discovery, :timelines, "global_feed_prewarm_interval_seconds", :integer, 30,
     min: 5, unit: :seconds, advanced: true},
    {:discovery, :timelines, "global_feed_prewarm_trending_tags", :integer, 12,
     min: 0, max: 100, advanced: true},
    {:discovery, :trending_tags, "trending_hashtag_window_hours", :integer, 168,
     min: 1, unit: :hours},
    {:discovery, :trending_tags, "trending_hashtag_min_posts", :integer, 2, min: 1},
    {:discovery, :trending_tags, "trending_hashtag_min_accounts", :integer, 2, min: 1},
    {:discovery, :explore, "explore_trending_refresh_seconds", :integer, 300,
     min: 30, unit: :seconds},
    {:discovery, :explore, "explore_trending_local_share", :number, 0.25, min: 0, max: 1},
    {:discovery, :explore, "explore_trending_window_hours_local", :number, 168,
     min: 1, unit: :hours},
    {:discovery, :explore, "explore_trending_window_hours_remote", :number, 72,
     min: 1, unit: :hours},
    {:discovery, :explore, "explore_trending_half_life_hours", :number, 24,
     min: 0.1, unit: :hours, advanced: true},
    {:discovery, :explore, "explore_trending_boost_weight", :number, 2.0, min: 0, advanced: true},
    {:discovery, :explore, "explore_trending_reply_weight", :number, 1.5, min: 0, advanced: true},
    {:discovery, :explore, "explore_trending_min_engagement_local", :number, 1,
     min: 0, advanced: true},
    {:discovery, :explore, "explore_trending_min_engagement_remote", :number, 3,
     min: 0, advanced: true},
    {:discovery, :explore, "explore_trending_min_fill_local", :number, 20,
     min: 0, advanced: true},
    {:discovery, :explore, "explore_trending_max_engagers_per_domain", :number, 10,
     min: 1, advanced: true},
    {:discovery, :explore, "explore_trending_max_candidates", :number, 2000,
     min: 1, advanced: true},
    {:discovery, :explore, "explore_trending_max_entries", :number, 500, min: 1, advanced: true},
    {:discovery, :explore, "explore_trending_top_tags", :number, 20, min: 0, advanced: true},
    {:discovery, :explore, "explore_trending_posts_per_tag", :number, 3, min: 0, advanced: true},
    {:discovery, :explore, "explore_trending_tag_bonus", :number, 5.0, min: 0, advanced: true},
    {:discovery, :explore, "explore_trending_tag_min_engagement", :number, 1,
     min: 0, advanced: true},
    {:discovery, :explore, "explore_trending_max_tags_per_post", :number, 8,
     min: 1, advanced: true},
    {:discovery, :explore, "explore_trending_top_accounts", :number, 20, min: 0, advanced: true},
    {:discovery, :explore, "explore_trending_account_bonus", :number, 3.0,
     min: 0, advanced: true},
    {:discovery, :explore, "explore_trending_account_min_engagement", :number, 3,
     min: 0, advanced: true},
    {:discovery, :explore, "explore_trending_author_penalty", :number, 1.5,
     min: 1, advanced: true},
    {:discovery, :explore, "explore_trending_retired_ttl_hours", :number, 6,
     min: 0, unit: :hours, advanced: true},
    {:discovery, :explore, "streams_trending_decay_seconds", :integer, 45_000,
     min: 60, unit: :seconds, advanced: true},
    {:discovery, :search, "search_backend", {:enum, ~w(postgresql meilisearch opensearch)},
     "postgresql", []},
    {:discovery, :search, "meilisearch_url", :string, "http://localhost:7700",
     @url ++ [visible_when: {"search_backend", "meilisearch"}]},
    {:discovery, :search, "meilisearch_api_key", :string, "",
     @secret ++ [visible_when: {"search_backend", "meilisearch"}]},

    # --- Federation ----------------------------------------------------------
    {:federation, :delivery, "federation_enabled", :boolean, true, []},
    {:federation, :delivery, "federation_retry_window_hours", :integer, 48,
     min: 1, max: 720, unit: :hours},
    {:federation, :delivery, "federation_key_cache_seconds", :integer, 3600,
     min: 60, unit: :seconds, advanced: true},
    {:federation, :dead_actors, "federation_dead_actor_cleanup_enabled", :boolean, true, []},
    {:federation, :dead_actors, "federation_dead_actor_failure_threshold", :integer, 5,
     min: 1, max: 100},
    {:federation, :dead_actors, "federation_dead_actor_purge_content", :boolean, false, []},
    {:federation, :filters, "mrf_keyword_reject", :string_list, [], []},
    {:federation, :filters, "mrf_hellthread_threshold", :integer, 10, min: 1, max: 1000},
    {:federation, :filters, "mrf_activity_expiration_days", :integer, 365, min: 1, unit: :days},
    {:federation, :filters, "instance_actor_legacy_usernames", :string_list, [], @adv},

    # --- Moderation & safety -------------------------------------------------
    {:moderation, :report_emails, "report_email_notifications_enabled", :boolean, false, []},
    {:moderation, :report_emails, "report_email_throttle_seconds", :integer, 60,
     min: 0, unit: :seconds},
    {:moderation, :report_emails, "moderation_email_throttle_seconds", :integer, 600,
     min: 0, unit: :seconds},
    {:moderation, :escalation, "group_report_escalation_hours", :integer, 72,
     min: 1, unit: :hours},
    {:moderation, :content_filter, "content_filter_engine", {:enum, ~w(default custom none)},
     "default", []},
    {:moderation, :content_filter, "content_filter_webhook_url", :string, "",
     @url ++ [visible_when: {"content_filter_engine", "custom"}]},
    {:moderation, :takedowns, "takedown_purge_enabled", :boolean, false, []},
    {:moderation, :takedowns, "takedown_reminder_lead_days", :integer, 7, min: 0, unit: :days},

    # --- Rate limits ---------------------------------------------------------
    {:rate_limits, :api, "rate_limit_authenticated", :integer, 1200, min: 1, unit: :per_minute},
    {:rate_limits, :api, "rate_limit_anonymous", :integer, 240, min: 1, unit: :per_minute},
    {:rate_limits, :api, "rate_limit_federation", :integer, 1800, min: 1, unit: :per_minute},
    {:rate_limits, :auth, "rate_limit_login", :integer, 10, min: 1, unit: :per_15_minutes},
    {:rate_limits, :auth, "rate_limit_2fa", :integer, 5, min: 1, unit: :per_15_minutes},
    {:rate_limits, :auth, "rate_limit_oauth_token", :integer, 30, min: 1, unit: :per_15_minutes},
    {:rate_limits, :auth, "rate_limit_register", :integer, 20, min: 1, unit: :per_hour},
    {:rate_limits, :auth, "rate_limit_password_reset", :integer, 5, min: 1, unit: :per_hour},
    {:rate_limits, :auth, "rate_limit_recover", :integer, 5, min: 1, unit: :per_hour},
    {:rate_limits, :auth, "rate_limit_resend_confirmation", :integer, 2, min: 1, unit: :per_hour},
    {:rate_limits, :auth, "rate_limit_app_registration", :integer, 10, min: 1, unit: :per_hour},

    # --- Monetization --------------------------------------------------------
    {:monetization, :tiers, "tiers_enabled", :boolean, false, []},
    {:monetization, :tiers, "tiers_payment_configured", :boolean, false, []},
    {:monetization, :tiers, "subscription_currency", :string, "USD", max_length: 3},
    {:monetization, :tiers, "tier_verified_starter_price", :integer, 499, min: 0, unit: :cents},
    {:monetization, :tiers, "tier_verified_creator_price", :integer, 999, min: 0, unit: :cents},
    {:monetization, :tiers, "tier_verified_pro_price", :integer, 1999, min: 0, unit: :cents},
    {:monetization, :payments, "payment_gateway", {:enum, ~w(noop stripe paypal crypto)}, "noop",
     []},
    {:monetization, :payments, "stripe_secret_key", :string, "",
     @secret ++ [visible_when: {"payment_gateway", "stripe"}]},
    {:monetization, :payments, "stripe_webhook_secret", :string, "",
     @secret ++ [visible_when: {"payment_gateway", "stripe"}]},
    {:monetization, :payments, "paypal_mode", {:enum, ~w(sandbox live)}, "sandbox",
     visible_when: {"payment_gateway", "paypal"}},
    {:monetization, :payments, "paypal_client_id", :string, "",
     max_length: 512, visible_when: {"payment_gateway", "paypal"}},
    {:monetization, :payments, "paypal_secret", :string, "",
     @secret ++ [visible_when: {"payment_gateway", "paypal"}]},
    {:monetization, :payments, "paypal_webhook_id", :string, "",
     max_length: 512, visible_when: {"payment_gateway", "paypal"}},
    {:monetization, :payments, "crypto_payment_url", :string, "",
     @url ++ [visible_when: {"payment_gateway", "crypto"}]},
    {:monetization, :payments, "crypto_store_id", :string, "",
     max_length: 512, visible_when: {"payment_gateway", "crypto"}},
    {:monetization, :payments, "crypto_api_key", :string, "",
     @secret ++ [visible_when: {"payment_gateway", "crypto"}]},
    {:monetization, :payments, "crypto_webhook_secret", :string, "",
     @secret ++ [visible_when: {"payment_gateway", "crypto"}]},
    {:monetization, :premium, "premium_1char_handle_enabled", :boolean, false, []},
    {:monetization, :premium, "premium_2char_handle_enabled", :boolean, false, []},
    {:monetization, :premium, "premium_3char_handle_enabled", :boolean, false, []},
    {:monetization, :premium, "ads_enabled", :boolean, false, []},

    # --- Integrations --------------------------------------------------------
    {:integrations, :notifications, "notification_channels", :string, "push", max_length: 100},
    {:integrations, :notifications, "notification_from_email", :string, "notifications@localhost",
     max_length: 254},
    {:integrations, :sms, "sms_provider_url", :string, "", @url},
    {:integrations, :sms, "sms_from_number", :string, "", max_length: 32},
    {:integrations, :sms, "sms_api_key", :string, "", @secret},
    {:integrations, :analytics, "analytics_provider",
     {:enum, ~w(none plausible umami matomo rybbit google)}, "none", []},
    {:integrations, :analytics, "analytics_host", :string, "", @url},
    {:integrations, :analytics, "analytics_site_id", :string, "", max_length: 255},
    {:integrations, :media_search, "giphy_api_key", :string, "", @secret},

    # --- Data retention ------------------------------------------------------
    {:retention, :records, "report_retention_days", :integer, 90, min: 1, unit: :days},
    {:retention, :records, "appeal_retention_days", :integer, 90, min: 1, unit: :days},
    {:retention, :records, "takedown_retention_days", :integer, 60, min: 1, unit: :days},
    {:retention, :records, "metrics_retention_days", :integer, 30, min: 1, unit: :days},
    {:retention, :records, "backup_retention_days", :integer, 30, min: 1, unit: :days},
    # 0 keeps delivery rows forever.
    {:retention, :records, "federation_delivery_retention_days", :integer, 30,
     min: 0, unit: :days}
  ]

  @static (for {group, section, key, type, default, opts} <- @spec_rows do
             opts
             |> Map.new()
             |> Map.merge(%{
               key: key,
               type: type,
               group: group,
               section: section,
               default: default
             })
           end)

  @static_by_key Map.new(@static, &{&1.key, &1})

  if map_size(@static_by_key) != length(@static), do: raise("duplicate registry key")

  for %{group: g} <- @static, not Keyword.has_key?(@groups, g) do
    raise "registry group #{inspect(g)} has no permission"
  end

  # Names that are secret whether or not they are registered, so a key added
  # later by a dedicated endpoint is still never echoed back by the generic API.
  @secret_name ~r/(secret|api_key|private_key|access_key|password|token)$/

  @markdown_levels ~w(none basic full full_embeds)

  # Settings deliberately left out of the registry: owned by a dedicated admin
  # endpoint, generated by the system, or structured values that need their
  # own editor. A test checks every `Config.get("...")` key in lib/ is either
  # registered or matched here, so new tunables can't silently skip the panel.
  @unmanaged_prefixes ~w(theme_ email_ translation_ vapid_ instance_og_image)
  @unmanaged ~w(app_icon_source instance_rules mrf_policies mrf_keyword_replace upload_filters)

  @doc "Whether `key` is intentionally managed outside the registry."
  @spec unmanaged?(String.t()) :: boolean()
  def unmanaged?(key) do
    key in @unmanaged or Enum.any?(@unmanaged_prefixes, &String.starts_with?(key, &1))
  end

  @doc "Settings groups in display order, as `{group, permission}`."
  @spec groups() :: [{atom(), String.t()}]
  def groups, do: @groups

  @doc "The permission that guards writes to `group`."
  @spec permission_for(atom()) :: String.t() | nil
  def permission_for(group), do: Keyword.get(@groups, group)

  @doc "Every registered entry, including the generated per-tier limits."
  @spec entries() :: [entry()]
  def entries, do: @static ++ tier_entries()

  @doc "The entry for `key`, or `nil` when the key isn't writable through the generic API."
  @spec fetch(String.t()) :: entry() | nil
  def fetch(key) when is_binary(key) do
    Map.get(@static_by_key, key) || tier_entry(key)
  end

  def fetch(_), do: nil

  @doc "Whether a key's value must never be returned by the API or written to the audit log."
  @spec secret?(String.t()) :: boolean()
  def secret?(key) when is_binary(key) do
    case fetch(key) do
      %{secret: true} -> true
      _ -> Regex.match?(@secret_name, key)
    end
  end

  def secret?(_), do: false

  @doc """
  Cast `value` to the type `key` declares, enforcing bounds.

  Returns `{:ok, cast}`, `{:error, :unknown_key}`, or `{:error, reason}`.
  """
  @spec cast(String.t(), term()) :: {:ok, term()} | {:error, atom()}
  def cast(key, value) do
    case fetch(key) do
      nil -> {:error, :unknown_key}
      entry -> cast_entry(entry, value)
    end
  end

  @doc """
  Best-effort typing for a stored value: the cast value when `key` is
  registered and `value` casts cleanly, otherwise `value` untouched.

  Used when loading settings into the cache, so rows written as strings before
  the registry existed (`"800"`, `"true"`) read back as the type their readers
  compare against.
  """
  @spec normalize(String.t(), term()) :: term()
  def normalize(key, value) do
    case cast(key, value) do
      {:ok, cast} -> cast
      {:error, _} -> value
    end
  end

  # --- casting ---

  defp cast_entry(%{nullable: true}, value) when value in [nil, ""], do: {:ok, nil}

  defp cast_entry(%{type: :boolean}, value) when is_boolean(value), do: {:ok, value}
  defp cast_entry(%{type: :boolean}, "true"), do: {:ok, true}
  defp cast_entry(%{type: :boolean}, "false"), do: {:ok, false}
  defp cast_entry(%{type: :boolean}, _), do: {:error, :invalid_boolean}

  defp cast_entry(%{type: :integer} = entry, value) do
    with {:ok, int} <- to_integer(value), do: check_bounds(entry, int)
  end

  defp cast_entry(%{type: :number} = entry, value) do
    with {:ok, num} <- to_number(value), do: check_bounds(entry, num)
  end

  defp cast_entry(%{type: :string} = entry, value) when is_binary(value) do
    if String.length(value) <= Map.get(entry, :max_length, 10_000),
      do: {:ok, value},
      else: {:error, :too_long}
  end

  defp cast_entry(%{type: :string}, _), do: {:error, :invalid_string}

  defp cast_entry(%{type: :string_list}, value) when is_list(value) do
    if Enum.all?(value, &(is_binary(&1) and String.length(&1) <= 500)) and length(value) <= 1000 do
      {:ok, value |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == "")) |> Enum.uniq()}
    else
      {:error, :invalid_list}
    end
  end

  defp cast_entry(%{type: :string_list}, _), do: {:error, :invalid_list}

  defp cast_entry(%{type: {:enum, values}}, value) when is_binary(value) do
    if value in values, do: {:ok, value}, else: {:error, :invalid_option}
  end

  defp cast_entry(%{type: {:enum, _}}, _), do: {:error, :invalid_option}

  defp to_integer(value) when is_integer(value), do: {:ok, value}

  defp to_integer(value) when is_float(value) do
    if value == Float.round(value), do: {:ok, trunc(value)}, else: {:error, :invalid_integer}
  end

  defp to_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> {:ok, int}
      _ -> {:error, :invalid_integer}
    end
  end

  defp to_integer(_), do: {:error, :invalid_integer}

  defp to_number(value) when is_number(value), do: {:ok, value}

  defp to_number(value) when is_binary(value) do
    trimmed = String.trim(value)

    case Integer.parse(trimmed) do
      {int, ""} ->
        {:ok, int}

      _ ->
        case Float.parse(trimmed) do
          {float, ""} -> {:ok, float}
          _ -> {:error, :invalid_number}
        end
    end
  end

  defp to_number(_), do: {:error, :invalid_number}

  defp check_bounds(entry, n) do
    cond do
      Map.has_key?(entry, :min) and n < entry.min -> {:error, :below_minimum}
      Map.has_key?(entry, :max) and n > entry.max -> {:error, :above_maximum}
      true -> {:ok, n}
    end
  end

  # --- per-tier limits, derived from TierLimits defaults (Tiers page) ---

  defp tier_entries do
    Enum.flat_map(TierLimits.tiers(), fn tier ->
      [tier_name_entry(tier) | Enum.map(TierLimits.limit_keys(), &tier_limit_entry(tier, &1))]
    end)
  end

  defp tier_entry("tier_" <> rest) do
    Enum.find_value(TierLimits.tiers(), fn tier ->
      case String.split(rest, tier <> "_", parts: 2) do
        ["", "name"] ->
          tier_name_entry(tier)

        ["", limit] ->
          atom = Enum.find(TierLimits.limit_keys(), &(Atom.to_string(&1) == limit))
          atom && tier_limit_entry(tier, atom)

        _ ->
          nil
      end
    end)
  end

  defp tier_entry(_), do: nil

  defp tier_name_entry(tier) do
    tier_base("tier_#{tier}_name", TierLimits.default_tier_names()[tier])
    |> Map.merge(%{type: :string, max_length: 50})
  end

  defp tier_limit_entry(tier, :markdown) do
    tier_base("tier_#{tier}_markdown", TierLimits.defaults()[tier][:markdown])
    |> Map.put(:type, {:enum, @markdown_levels})
  end

  defp tier_limit_entry(tier, limit) do
    default = TierLimits.defaults()[tier][limit]
    base = tier_base("tier_#{tier}_#{limit}", default)

    if is_boolean(default),
      do: Map.put(base, :type, :boolean),
      else: Map.merge(base, %{type: :integer, min: 0})
  end

  defp tier_base(key, default) do
    %{key: key, group: :monetization, section: :tier_limits, default: default, page: :tiers}
  end
end
