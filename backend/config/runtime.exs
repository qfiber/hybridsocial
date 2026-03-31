import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/hybridsocial start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :hybridsocial, HybridsocialWeb.Endpoint, server: true
end

if config_env() != :test do
  config :hybridsocial, HybridsocialWeb.Endpoint,
    http: [port: String.to_integer(System.get_env("PORT", "4000"))]
end

# Instance actor RSA keypair — used for relay and instance-level federation signing.
# Generate with: mix run -e "Hybridsocial.Federation.InstanceActor.generate_keys_to_stdout()"
# Or let docker compose generate them on first startup.
if instance_public_key = System.get_env("INSTANCE_PUBLIC_KEY") do
  decoded = case Base.decode64(instance_public_key) do
    {:ok, pem} -> pem
    _ -> instance_public_key
  end
  config :hybridsocial, :instance_public_key, decoded
end

if instance_private_key = System.get_env("INSTANCE_PRIVATE_KEY") do
  decoded = case Base.decode64(instance_private_key) do
    {:ok, pem} -> pem
    _ -> instance_private_key
  end
  config :hybridsocial, :instance_private_key, decoded
end

# Media host — separate domain/subdomain for serving user uploads (security)
# Must match Caddy/reverse proxy config. Example: https://media.hybridsocial.com
if media_host = System.get_env("MEDIA_HOST") do
  config :hybridsocial, :media_host, media_host
end

# Log level — set LOG_LEVEL=debug in .env for verbose output
if log_level = System.get_env("LOG_LEVEL") do
  config :logger, level: String.to_existing_atom(log_level)
end

# Service URLs — override defaults for Docker/production
if valkey_url = System.get_env("VALKEY_URL") do
  config :hybridsocial, :valkey_url, valkey_url
end

if opensearch_url = System.get_env("OPENSEARCH_URL") do
  config :hybridsocial, :opensearch_url, opensearch_url
end

if search_backend = System.get_env("SEARCH_BACKEND") do
  config :hybridsocial, :search_backend, search_backend
end

if nats_url = System.get_env("NATS_URL") do
  config :hybridsocial,
    nats_url: nats_url,
    nats_host: System.get_env("NATS_HOST", URI.parse(nats_url).host || "localhost"),
    nats_port: String.to_integer(System.get_env("NATS_PORT", to_string(URI.parse(nats_url).port || 4222))),
    nats_monitoring_port: String.to_integer(System.get_env("NATS_MONITORING_PORT", "8222"))
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :hybridsocial, Hybridsocial.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :hybridsocial, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :hybridsocial, HybridsocialWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # CORS origins for production
  config :hybridsocial, :cors_origins, [System.get_env("FRONTEND_URL", "https://#{host}")]

  # Email - check for Resend first, fall back to SMTP
  if resend_key = System.get_env("RESEND_API_KEY") do
    config :hybridsocial, Hybridsocial.Mailer,
      adapter: Swoosh.Adapters.Resend,
      api_key: resend_key
  else
    smtp_host = System.get_env("SMTP_HOST")

    if smtp_host do
      config :hybridsocial, Hybridsocial.Mailer,
        adapter: Swoosh.Adapters.SMTP,
        relay: smtp_host,
        port: String.to_integer(System.get_env("SMTP_PORT", "587")),
        username: System.get_env("SMTP_USER"),
        password: System.get_env("SMTP_PASS"),
        tls: :always
    end
  end

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :hybridsocial, HybridsocialWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :hybridsocial, HybridsocialWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
