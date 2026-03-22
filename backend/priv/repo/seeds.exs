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
  }
]

for attrs <- settings do
  %Setting{}
  |> Setting.changeset(attrs)
  |> Repo.insert!(on_conflict: :nothing, conflict_target: :key)
end
