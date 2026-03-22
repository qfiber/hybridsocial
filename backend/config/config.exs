# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :hybridsocial,
  ecto_repos: [Hybridsocial.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true],
  env: config_env()

# Register event-stream MIME type for SSE
config :mime, :types, %{
  "text/event-stream" => ["event-stream"]
}

# Configure the endpoint
config :hybridsocial, HybridsocialWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: HybridsocialWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Hybridsocial.PubSub,
  live_view: [signing_salt: "TTdY2MXz"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# ExAws S3 configuration
config :ex_aws,
  access_key_id: [{:system, "S3_ACCESS_KEY_ID"}, :instance_role],
  secret_access_key: [{:system, "S3_SECRET_ACCESS_KEY"}, :instance_role],
  region: {:system, "S3_REGION"}

# Swoosh mailer configuration
config :hybridsocial, Hybridsocial.Mailer,
  adapter: Swoosh.Adapters.Local

# Valkey (Redis-compatible) cache
config :hybridsocial, :valkey_url, System.get_env("VALKEY_URL", "redis://localhost:6379")

# OpenSearch configuration
config :hybridsocial, :opensearch_url, System.get_env("OPENSEARCH_URL", "http://localhost:9200")
config :hybridsocial, :search_backend, System.get_env("SEARCH_BACKEND", "postgresql")

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
