# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Hybridsocial.Repo.insert!(%Hybridsocial.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Hybridsocial.Config.Setting
alias Hybridsocial.Repo

settings = [
  # General
  %{
    key: "instance_name",
    value: %{"value" => "HybridSocial"},
    type: "string",
    category: "general",
    description: "The name of this instance"
  },
  %{
    key: "instance_description",
    value: %{"value" => ""},
    type: "string",
    category: "general",
    description: "A short description of this instance"
  },
  %{
    key: "instance_thumbnail",
    value: %{"value" => ""},
    type: "string",
    category: "general",
    description: "URL to the instance thumbnail/logo image"
  },
  %{
    key: "instance_short_description",
    value: %{"value" => ""},
    type: "string",
    category: "general",
    description: "Short tagline for the instance"
  },
  %{
    key: "instance_rules",
    value: %{"value" => ["There should be neither harming nor reciprocating harm."]},
    type: "json",
    category: "general",
    description: "List of instance rules (JSON array of strings)"
  },
  %{
    key: "instance_languages",
    value: %{"value" => "en"},
    type: "string",
    category: "general",
    description: "Comma-separated language codes (e.g. en,ar,fr)"
  },
  %{
    key: "instance_background_image",
    value: %{"value" => ""},
    type: "string",
    category: "general",
    description: "URL to the instance background image"
  },
  %{
    key: "contact_account_handle",
    value: %{"value" => ""},
    type: "string",
    category: "general",
    description: "Handle of the contact account (e.g. admin)"
  },
  %{
    key: "max_avatar_size",
    value: %{"value" => 2_000_000},
    type: "integer",
    category: "media",
    description: "Maximum avatar upload size in bytes (default 2MB)"
  },
  %{
    key: "max_banner_size",
    value: %{"value" => 4_000_000},
    type: "integer",
    category: "media",
    description: "Maximum banner/header upload size in bytes (default 4MB)"
  },
  %{
    key: "max_background_size",
    value: %{"value" => 4_000_000},
    type: "integer",
    category: "media",
    description: "Maximum background image upload size in bytes (default 4MB)"
  },
  %{
    key: "video_frame_rate_limit",
    value: %{"value" => 120},
    type: "integer",
    category: "media",
    description: "Maximum video frame rate"
  },
  %{
    key: "video_matrix_limit",
    value: %{"value" => 8_294_400},
    type: "integer",
    category: "media",
    description: "Maximum video resolution (width * height)"
  },
  %{
    key: "image_matrix_limit",
    value: %{"value" => 33_177_600},
    type: "integer",
    category: "media",
    description: "Maximum image resolution (width * height)"
  },

  # Limits
  %{
    key: "max_poll_options",
    value: %{"value" => 4},
    type: "integer",
    category: "limits",
    description: "Maximum number of poll options"
  },
  %{
    key: "max_poll_option_chars",
    value: %{"value" => 200},
    type: "integer",
    category: "limits",
    description: "Maximum characters per poll option"
  },
  %{
    key: "min_poll_expiration",
    value: %{"value" => 300},
    type: "integer",
    category: "limits",
    description: "Minimum poll expiration in seconds (default 5 minutes)"
  },
  %{
    key: "max_poll_expiration",
    value: %{"value" => 2_629_746},
    type: "integer",
    category: "limits",
    description: "Maximum poll expiration in seconds (default ~30 days)"
  },
  %{
    key: "max_featured_tags",
    value: %{"value" => 10},
    type: "integer",
    category: "limits",
    description: "Maximum featured/pinned hashtags per profile"
  },
  %{
    key: "characters_reserved_per_url",
    value: %{"value" => 23},
    type: "integer",
    category: "limits",
    description: "Characters reserved per URL in posts"
  },
  %{
    key: "max_profile_fields",
    value: %{"value" => 5},
    type: "integer",
    category: "limits",
    description: "Maximum custom profile fields"
  },
  %{
    key: "max_field_name_length",
    value: %{"value" => 512},
    type: "integer",
    category: "limits",
    description: "Maximum profile field name length"
  },
  %{
    key: "max_field_value_length",
    value: %{"value" => 2048},
    type: "integer",
    category: "limits",
    description: "Maximum profile field value length"
  },
  %{
    key: "contact_email",
    value: %{"value" => ""},
    type: "string",
    category: "general",
    description: "Contact email for this instance"
  },

  # Limits
  %{
    key: "max_post_length_free",
    value: %{"value" => 5000},
    type: "integer",
    category: "limits",
    description: "Maximum post length for free users"
  },
  %{
    key: "max_post_length_premium",
    value: %{"value" => 10_000},
    type: "integer",
    category: "limits",
    description: "Maximum post length for premium users"
  },
  %{
    key: "max_media_per_post",
    value: %{"value" => 4},
    type: "integer",
    category: "limits",
    description: "Maximum number of media attachments per post"
  },
  %{
    key: "max_image_size_mb",
    value: %{"value" => 10},
    type: "integer",
    category: "limits",
    description: "Maximum image file size in megabytes"
  },
  %{
    key: "max_video_size_mb",
    value: %{"value" => 100},
    type: "integer",
    category: "limits",
    description: "Maximum video file size in megabytes"
  },
  %{
    key: "max_video_duration_seconds",
    value: %{"value" => 300},
    type: "integer",
    category: "limits",
    description: "Maximum video duration in seconds"
  },
  %{
    key: "max_stream_duration_seconds",
    value: %{"value" => 90},
    type: "integer",
    category: "limits",
    description: "Maximum stream duration in seconds"
  },
  %{
    key: "post_edit_window_seconds",
    value: %{"value" => 86_400},
    type: "integer",
    category: "limits",
    description: "Time window in seconds during which a post can be edited"
  },

  # Registration
  %{
    key: "registration_mode",
    value: %{"value" => "open"},
    type: "string",
    category: "registration",
    description: "Registration mode: open, approval, or closed"
  },
  %{
    key: "require_email_confirmation",
    value: %{"value" => true},
    type: "boolean",
    category: "registration",
    description: "Whether email confirmation is required for new accounts"
  },

  # Federation
  %{
    key: "federation_enabled",
    value: %{"value" => true},
    type: "boolean",
    category: "federation",
    description: "Whether federation with other instances is enabled"
  },

  # Media / Storage
  %{
    key: "storage_backend",
    value: %{"value" => "local"},
    type: "string",
    category: "media",
    description: "Storage backend for media uploads: local or s3"
  },
  %{
    key: "media_host",
    value: %{"value" => ""},
    type: "string",
    category: "media",
    description:
      "Base URL for media serving (e.g. https://media.example.com). Leave empty to use relative URLs."
  },
  %{
    key: "s3_bucket",
    value: %{"value" => ""},
    type: "string",
    category: "media",
    description: "S3 bucket name for media storage"
  },
  %{
    key: "s3_region",
    value: %{"value" => ""},
    type: "string",
    category: "media",
    description: "S3 region (e.g. us-east-1)"
  },
  %{
    key: "s3_endpoint",
    value: %{"value" => ""},
    type: "string",
    category: "media",
    description: "Custom S3 endpoint for S3-compatible services (e.g. MinIO)"
  },

  # Search
  %{
    key: "search_backend",
    value: %{"value" => "postgresql"},
    type: "string",
    category: "search",
    description: "Search backend: postgresql or opensearch"
  },
  %{
    key: "opensearch_url",
    value: %{"value" => "http://localhost:9200"},
    type: "string",
    category: "search",
    description: "OpenSearch server URL"
  },

  # Security
  %{
    key: "rate_limit_authenticated",
    value: %{"value" => 300},
    type: "integer",
    category: "security",
    description: "Rate limit per interval for authenticated users"
  },
  %{
    key: "rate_limit_anonymous",
    value: %{"value" => 60},
    type: "integer",
    category: "security",
    description: "Rate limit per minute for anonymous users"
  },
  %{
    key: "rate_limit_login",
    value: %{"value" => 10},
    type: "integer",
    category: "security",
    description: "Login attempts per 15 minutes per IP"
  },
  %{
    key: "rate_limit_register",
    value: %{"value" => 5},
    type: "integer",
    category: "security",
    description: "Registration attempts per hour per IP"
  },
  %{
    key: "rate_limit_password_reset",
    value: %{"value" => 5},
    type: "integer",
    category: "security",
    description: "Password reset requests per hour per IP"
  },
  %{
    key: "rate_limit_2fa",
    value: %{"value" => 5},
    type: "integer",
    category: "security",
    description: "2FA verification attempts per 15 minutes per user"
  },
  %{
    key: "max_json_payload_bytes",
    value: %{"value" => 1_000_000},
    type: "integer",
    category: "security",
    description: "Maximum JSON request body size in bytes (default 1MB)"
  },
  %{
    key: "max_upload_payload_bytes",
    value: %{"value" => 100_000_000},
    type: "integer",
    category: "security",
    description: "Maximum file upload size in bytes (default 100MB)"
  },
  %{
    key: "max_federation_payload_bytes",
    value: %{"value" => 1_000_000},
    type: "integer",
    category: "security",
    description: "Maximum federation inbox payload size in bytes (default 1MB)"
  },
  %{
    key: "vapid_public_key",
    value: %{"value" => ""},
    type: "string",
    category: "security",
    description: "VAPID public key for web push notifications (auto-generated)"
  },
  %{
    key: "vapid_private_key",
    value: %{"value" => ""},
    type: "string",
    category: "security",
    description: "VAPID private key for web push notifications (auto-generated, keep secret)"
  },

  # Mobile Apps
  %{
    key: "app_ios_url",
    value: %{"value" => ""},
    type: "string",
    category: "apps",
    description: "App Store URL for the iOS app"
  },
  %{
    key: "app_android_url",
    value: %{"value" => ""},
    type: "string",
    category: "apps",
    description: "Google Play Store URL for the Android app"
  },
  %{
    key: "app_fdroid_url",
    value: %{"value" => ""},
    type: "string",
    category: "apps",
    description: "F-Droid URL for the Android app"
  },
  %{
    key: "app_banner_enabled",
    value: %{"value" => false},
    type: "boolean",
    category: "apps",
    description: "Show mobile app download banner to mobile users"
  },

  # Promotions
  %{
    key: "promotions_enabled",
    value: %{"value" => true},
    type: "boolean",
    category: "premium",
    description: "Allow users to purchase profile promotions"
  },
  %{
    key: "promotion_price_cents",
    value: %{"value" => 150},
    type: "integer",
    category: "premium",
    description: "Price in cents for a promotion package (e.g. 150 = $1.50)"
  },
  %{
    key: "promotion_duration_days",
    value: %{"value" => 30},
    type: "integer",
    category: "premium",
    description: "How many days a promotion lasts"
  },
  %{
    key: "promotion_max_active",
    value: %{"value" => 10},
    type: "integer",
    category: "premium",
    description: "Maximum number of promoted users shown in the sidebar"
  },

  # Analytics
  %{
    key: "analytics_provider",
    value: %{"value" => "none"},
    type: "string",
    category: "general",
    description: "Analytics provider: none, google, plausible, matomo, umami, or rybbit"
  },
  %{
    key: "analytics_site_id",
    value: %{"value" => ""},
    type: "string",
    category: "general",
    description:
      "Site/measurement ID for the analytics provider (e.g. G-XXXXXXX for Google, website ID for Umami)"
  },
  %{
    key: "analytics_host",
    value: %{"value" => ""},
    type: "string",
    category: "general",
    description: "Self-hosted analytics URL (required for Plausible, Matomo, Umami, Rybbit)"
  },

  # === Reserved Handles ===
  %{
    key: "reserved_handles",
    value: %{
      "value" => [
        "admin",
        "administrator",
        "mod",
        "moderator",
        "owner",
        "staff",
        "support",
        "help",
        "system",
        "root",
        "superuser",
        "hybridsocial",
        "official",
        "verified",
        "security",
        "abuse",
        "postmaster",
        "webmaster",
        "noreply",
        "null",
        "undefined",
        "api",
        "www",
        "mail",
        "ftp",
        "bot",
        "status",
        "billing",
        "legal",
        "terms",
        "privacy",
        "about",
        "explore",
        "home",
        "settings",
        "notifications",
        "messages",
        "login",
        "register",
        "auth",
        "oauth",
        "search",
        "trending",
        "groups",
        "pages"
      ]
    },
    type: "json",
    category: "registration",
    description: "List of handles that cannot be registered by users"
  },

  # === Premium Short Handles ===
  %{
    key: "premium_1char_handle_enabled",
    value: %{"value" => false},
    type: "boolean",
    category: "premium",
    description: "Restrict 1-character handles to premium purchase only"
  },
  %{
    key: "premium_1char_handle_price_cents",
    value: %{"value" => 10000},
    type: "integer",
    category: "premium",
    description: "One-time price in cents for a 1-character handle (e.g. 10000 = $100)"
  },
  %{
    key: "premium_2char_handle_enabled",
    value: %{"value" => false},
    type: "boolean",
    category: "premium",
    description: "Restrict 2-character handles to premium purchase only"
  },
  %{
    key: "premium_2char_handle_price_cents",
    value: %{"value" => 2500},
    type: "integer",
    category: "premium",
    description: "One-time price in cents for a 2-character handle (e.g. 2500 = $25)"
  },
  %{
    key: "premium_3char_handle_enabled",
    value: %{"value" => false},
    type: "boolean",
    category: "premium",
    description: "Restrict 3-character handles to premium purchase only"
  },
  %{
    key: "premium_3char_handle_price_cents",
    value: %{"value" => 500},
    type: "integer",
    category: "premium",
    description: "One-time price in cents for a 3-character handle (e.g. 500 = $5)"
  },

  # === Verification Tiers ===
  %{
    key: "tiers_enabled",
    value: %{"value" => false},
    type: "boolean",
    category: "tiers",
    description: "Enable tiered verification limits (when off, all users get max limits)"
  },
  %{
    key: "tiers_payment_configured",
    value: %{"value" => false},
    type: "boolean",
    category: "tiers",
    description: "Whether a payment method is configured for tier upgrades"
  },

  # L0 — Free
  %{
    key: "tier_free_char_limit",
    value: %{"value" => 800},
    type: "integer",
    category: "tiers",
    description: "L0: Max characters per post"
  },
  %{
    key: "tier_free_markdown",
    value: %{"value" => "none"},
    type: "string",
    category: "tiers",
    description: "L0: Markdown level (none/basic/full/full_embeds)"
  },
  %{
    key: "tier_free_video_resolution",
    value: %{"value" => 720},
    type: "integer",
    category: "tiers",
    description: "L0: Max video resolution (720/1080)"
  },
  %{
    key: "tier_free_video_duration",
    value: %{"value" => 90},
    type: "integer",
    category: "tiers",
    description: "L0: Max video duration in seconds"
  },
  %{
    key: "tier_free_image_size_mb",
    value: %{"value" => 1},
    type: "integer",
    category: "tiers",
    description: "L0: Max image upload size in MB"
  },
  %{
    key: "tier_free_video_size_mb",
    value: %{"value" => 15},
    type: "integer",
    category: "tiers",
    description: "L0: Max video upload size in MB"
  },
  %{
    key: "tier_free_media_per_post",
    value: %{"value" => 2},
    type: "integer",
    category: "tiers",
    description: "L0: Max media attachments per post"
  },
  %{
    key: "tier_free_poll_options",
    value: %{"value" => 2},
    type: "integer",
    category: "tiers",
    description: "L0: Max poll options"
  },
  %{
    key: "tier_free_edit_window",
    value: %{"value" => 900},
    type: "integer",
    category: "tiers",
    description: "L0: Post edit window in seconds (0 = unlimited)"
  },
  %{
    key: "tier_free_pinned_posts",
    value: %{"value" => 1},
    type: "integer",
    category: "tiers",
    description: "L0: Max pinned posts"
  },
  %{
    key: "tier_free_profile_fields",
    value: %{"value" => 0},
    type: "integer",
    category: "tiers",
    description: "L0: Max custom profile fields"
  },
  %{
    key: "tier_free_scheduled_posts",
    value: %{"value" => false},
    type: "boolean",
    category: "tiers",
    description: "L0: Allow scheduled posts"
  },
  %{
    key: "tier_free_custom_emoji",
    value: %{"value" => false},
    type: "boolean",
    category: "tiers",
    description: "L0: Allow custom emoji creation"
  },
  %{
    key: "tier_free_follows_limit",
    value: %{"value" => 100},
    type: "integer",
    category: "tiers",
    description: "L0: Max follows (0 = unlimited)"
  },

  # L1 — Verified Starter
  %{
    key: "tier_verified_starter_char_limit",
    value: %{"value" => 1200},
    type: "integer",
    category: "tiers",
    description: "L1: Max characters per post"
  },
  %{
    key: "tier_verified_starter_markdown",
    value: %{"value" => "basic"},
    type: "string",
    category: "tiers",
    description: "L1: Markdown level"
  },
  %{
    key: "tier_verified_starter_video_resolution",
    value: %{"value" => 720},
    type: "integer",
    category: "tiers",
    description: "L1: Max video resolution"
  },
  %{
    key: "tier_verified_starter_video_duration",
    value: %{"value" => 200},
    type: "integer",
    category: "tiers",
    description: "L1: Max video duration in seconds"
  },
  %{
    key: "tier_verified_starter_image_size_mb",
    value: %{"value" => 3},
    type: "integer",
    category: "tiers",
    description: "L1: Max image upload size in MB"
  },
  %{
    key: "tier_verified_starter_video_size_mb",
    value: %{"value" => 20},
    type: "integer",
    category: "tiers",
    description: "L1: Max video upload size in MB"
  },
  %{
    key: "tier_verified_starter_media_per_post",
    value: %{"value" => 4},
    type: "integer",
    category: "tiers",
    description: "L1: Max media attachments per post"
  },
  %{
    key: "tier_verified_starter_poll_options",
    value: %{"value" => 4},
    type: "integer",
    category: "tiers",
    description: "L1: Max poll options"
  },
  %{
    key: "tier_verified_starter_edit_window",
    value: %{"value" => 1800},
    type: "integer",
    category: "tiers",
    description: "L1: Post edit window in seconds"
  },
  %{
    key: "tier_verified_starter_pinned_posts",
    value: %{"value" => 2},
    type: "integer",
    category: "tiers",
    description: "L1: Max pinned posts"
  },
  %{
    key: "tier_verified_starter_profile_fields",
    value: %{"value" => 2},
    type: "integer",
    category: "tiers",
    description: "L1: Max custom profile fields"
  },
  %{
    key: "tier_verified_starter_scheduled_posts",
    value: %{"value" => false},
    type: "boolean",
    category: "tiers",
    description: "L1: Allow scheduled posts"
  },
  %{
    key: "tier_verified_starter_custom_emoji",
    value: %{"value" => false},
    type: "boolean",
    category: "tiers",
    description: "L1: Allow custom emoji creation"
  },
  %{
    key: "tier_verified_starter_follows_limit",
    value: %{"value" => 0},
    type: "integer",
    category: "tiers",
    description: "L1: Max follows (0 = unlimited)"
  },

  # L2 — Verified Creator
  %{
    key: "tier_verified_creator_char_limit",
    value: %{"value" => 3000},
    type: "integer",
    category: "tiers",
    description: "L2: Max characters per post"
  },
  %{
    key: "tier_verified_creator_markdown",
    value: %{"value" => "full"},
    type: "string",
    category: "tiers",
    description: "L2: Markdown level"
  },
  %{
    key: "tier_verified_creator_video_resolution",
    value: %{"value" => 1080},
    type: "integer",
    category: "tiers",
    description: "L2: Max video resolution"
  },
  %{
    key: "tier_verified_creator_video_duration",
    value: %{"value" => 300},
    type: "integer",
    category: "tiers",
    description: "L2: Max video duration in seconds"
  },
  %{
    key: "tier_verified_creator_image_size_mb",
    value: %{"value" => 5},
    type: "integer",
    category: "tiers",
    description: "L2: Max image upload size in MB"
  },
  %{
    key: "tier_verified_creator_video_size_mb",
    value: %{"value" => 25},
    type: "integer",
    category: "tiers",
    description: "L2: Max video upload size in MB"
  },
  %{
    key: "tier_verified_creator_media_per_post",
    value: %{"value" => 6},
    type: "integer",
    category: "tiers",
    description: "L2: Max media attachments per post"
  },
  %{
    key: "tier_verified_creator_poll_options",
    value: %{"value" => 6},
    type: "integer",
    category: "tiers",
    description: "L2: Max poll options"
  },
  %{
    key: "tier_verified_creator_edit_window",
    value: %{"value" => 86400},
    type: "integer",
    category: "tiers",
    description: "L2: Post edit window in seconds"
  },
  %{
    key: "tier_verified_creator_pinned_posts",
    value: %{"value" => 5},
    type: "integer",
    category: "tiers",
    description: "L2: Max pinned posts"
  },
  %{
    key: "tier_verified_creator_profile_fields",
    value: %{"value" => 5},
    type: "integer",
    category: "tiers",
    description: "L2: Max custom profile fields"
  },
  %{
    key: "tier_verified_creator_scheduled_posts",
    value: %{"value" => true},
    type: "boolean",
    category: "tiers",
    description: "L2: Allow scheduled posts"
  },
  %{
    key: "tier_verified_creator_custom_emoji",
    value: %{"value" => false},
    type: "boolean",
    category: "tiers",
    description: "L2: Allow custom emoji creation"
  },
  %{
    key: "tier_verified_creator_follows_limit",
    value: %{"value" => 0},
    type: "integer",
    category: "tiers",
    description: "L2: Max follows (0 = unlimited)"
  },

  # L3 — Verified Pro
  %{
    key: "tier_verified_pro_char_limit",
    value: %{"value" => 5000},
    type: "integer",
    category: "tiers",
    description: "L3: Max characters per post"
  },
  %{
    key: "tier_verified_pro_markdown",
    value: %{"value" => "full_embeds"},
    type: "string",
    category: "tiers",
    description: "L3: Markdown level"
  },
  %{
    key: "tier_verified_pro_video_resolution",
    value: %{"value" => 1080},
    type: "integer",
    category: "tiers",
    description: "L3: Max video resolution"
  },
  %{
    key: "tier_verified_pro_video_duration",
    value: %{"value" => 600},
    type: "integer",
    category: "tiers",
    description: "L3: Max video duration in seconds"
  },
  %{
    key: "tier_verified_pro_image_size_mb",
    value: %{"value" => 10},
    type: "integer",
    category: "tiers",
    description: "L3: Max image upload size in MB"
  },
  %{
    key: "tier_verified_pro_video_size_mb",
    value: %{"value" => 40},
    type: "integer",
    category: "tiers",
    description: "L3: Max video upload size in MB"
  },
  %{
    key: "tier_verified_pro_media_per_post",
    value: %{"value" => 10},
    type: "integer",
    category: "tiers",
    description: "L3: Max media attachments per post"
  },
  %{
    key: "tier_verified_pro_poll_options",
    value: %{"value" => 10},
    type: "integer",
    category: "tiers",
    description: "L3: Max poll options"
  },
  %{
    key: "tier_verified_pro_edit_window",
    value: %{"value" => 0},
    type: "integer",
    category: "tiers",
    description: "L3: Post edit window in seconds (0 = unlimited)"
  },
  %{
    key: "tier_verified_pro_pinned_posts",
    value: %{"value" => 10},
    type: "integer",
    category: "tiers",
    description: "L3: Max pinned posts"
  },
  %{
    key: "tier_verified_pro_profile_fields",
    value: %{"value" => 10},
    type: "integer",
    category: "tiers",
    description: "L3: Max custom profile fields"
  },
  %{
    key: "tier_verified_pro_scheduled_posts",
    value: %{"value" => true},
    type: "boolean",
    category: "tiers",
    description: "L3: Allow scheduled posts"
  },
  %{
    key: "tier_verified_pro_custom_emoji",
    value: %{"value" => true},
    type: "boolean",
    category: "tiers",
    description: "L3: Allow custom emoji creation"
  },
  %{
    key: "tier_verified_pro_follows_limit",
    value: %{"value" => 0},
    type: "integer",
    category: "tiers",
    description: "L3: Max follows (0 = unlimited)"
  }
]

for attrs <- settings do
  %Setting{}
  |> Setting.changeset(attrs)
  |> Repo.insert!(on_conflict: :nothing, conflict_target: :key)
end

# Seed default site pages (privacy, terms, about)
alias Hybridsocial.SitePages.SitePage

placeholder = "This page is a placeholder, update it as you wish."
placeholder_html = "<p>This page is a placeholder, update it as you wish.</p>"

site_pages = [
  %{
    slug: "privacy",
    title: "Privacy Policy",
    body_markdown: placeholder,
    body_html: placeholder_html,
    published: true
  },
  %{
    slug: "terms",
    title: "Terms of Service",
    body_markdown: placeholder,
    body_html: placeholder_html,
    published: true
  },
  %{
    slug: "about",
    title: "About This Server",
    body_markdown: placeholder,
    body_html: placeholder_html,
    published: true
  }
]

import Ecto.Query

for attrs <- site_pages do
  exists =
    SitePage
    |> where([p], p.slug == ^attrs.slug and is_nil(p.deleted_at))
    |> Repo.exists?()

  unless exists do
    %SitePage{}
    |> SitePage.changeset(attrs)
    |> Repo.insert!()
  end
end
