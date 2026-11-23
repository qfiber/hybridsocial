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

# Fixed clock for PostRateLimit's calendar windows: a real one let a test's
# two posts straddle a minute boundary and both succeed (#321). Mid-minute,
# mid-hour, mid-day so retry_after stays a normal value.
config :hybridsocial, post_rate_limit_now: 1_800_001_830

# Skip HTTP signature verification in tests
config :hybridsocial, federation_signature_check: false

# Don't spawn fire-and-forget ActivityPub delivery tasks in tests. Those
# closures query the Repo and outlive the test, so they crash with a
# DBConnection.OwnershipError once the test's sandbox connection is
# checked back in. Tests that specifically exercise delivery flip this on.
config :hybridsocial, federation_delivery_enabled: false

# Use DB 1 for tests to avoid conflicts with dev data
config :hybridsocial, :valkey_url, "redis://localhost:6379/1"

# Fixed at-rest DM encryption key for deterministic tests.
config :hybridsocial,
       :message_encryption_key,
       "test-only-not-for-production-32byte!!!!"

# Fixed at-rest field-encryption key (private keys, 2FA secrets, emails).
config :hybridsocial,
       :data_encryption_key,
       "test-only-not-for-production-data-key!!!"

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
