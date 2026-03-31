import Config

# Force using SSL in production. This also sets the "strict-security-transport" header,
# known as HSTS. If you have a health check endpoint, you may want to exclude it below.
# Note `:force_ssl` is required to be set at compile-time.
config :hybridsocial, HybridsocialWeb.Endpoint,
  force_ssl: [
    rewrite_on: [:x_forwarded_proto],
    exclude: [
      # paths: ["/health"],
      hosts: ["localhost", "127.0.0.1"]
    ]
  ]

# Log level — override with LOG_LEVEL=debug in .env for troubleshooting
config :logger, level: :info

# Email - configured at runtime in config/runtime.exs based on SMTP or Resend env vars

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
