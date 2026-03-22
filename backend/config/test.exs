import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :hybridsocial, Hybridsocial.Repo,
  username: "hybridsocial",
  password: "hybridsocial_dev",
  hostname: "localhost",
  database: "hybridsocial_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :hybridsocial, HybridsocialWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "NpQL3N58Xo0h8wqBjzQXCJGmgWyNZ3yJAKgOnQzJ7b8Iybm25tz9a34GvtnJ05rL",
  server: false

# Use test adapter for emails
config :hybridsocial, Hybridsocial.Mailer, adapter: Swoosh.Adapters.Test

# Disable rate limiting in tests (individual rate limiter tests enable it manually)
config :hybridsocial, rate_limiting_enabled: false

# Skip HTTP signature verification in tests
config :hybridsocial, federation_signature_check: false

# Use DB 1 for tests to avoid conflicts with dev data
config :hybridsocial, :valkey_url, "redis://localhost:6379/1"

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
