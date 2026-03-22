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
    value: %{"value" => []},
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
  }
]

for attrs <- settings do
  %Setting{}
  |> Setting.changeset(attrs)
  |> Repo.insert!(on_conflict: :nothing, conflict_target: :key)
end
