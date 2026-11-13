defmodule Hybridsocial.MixProject do
  use Mix.Project

  def project do
    [
      app: :hybridsocial,
      version: "2026.11.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      listeners: [Phoenix.CodeReloader],
      test_coverage: [threshold: 60]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Hybridsocial.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.5"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.14"},
      {:postgrex, ">= 0.0.0"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      # Auth
      {:bcrypt_elixir, "~> 3.0"},
      {:joken, "~> 2.6"},
      # 2FA / TOTP
      {:nimble_totp, "~> 1.0"},
      # WebAuthn / FIDO2
      {:wax_, "~> 0.6"},
      # Utilities
      {:ecto_enum, "~> 1.4"},
      # S3 storage
      {:ex_aws, "~> 2.5"},
      {:ex_aws_s3, "~> 2.5"},
      {:sweet_xml, "~> 0.7"},
      # Email
      {:swoosh, "~> 1.17"},
      {:gen_smtp, "~> 1.0"},
      # Dev/Test tools
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      # Federation / HTTP (Req over Finch; replaced HTTPoison/hackney,
      # which was unmaintained and carried SSRF/CRLF CVEs)
      {:req, "~> 0.5"},
      # Valkey/Redis cache
      {:redix, "~> 1.5"},
      # CORS
      {:cors_plug, "~> 3.0"},
      # NATS JetStream
      {:gnat, "~> 1.8"},
      # Markdown (CommonMark + GFM) and HTML sanitization. MDEx (comrak)
      # replaced Earmark, which is retired/unmaintained with an open CVE.
      {:mdex, "~> 0.13"},
      {:html_sanitize_ex, "~> 1.4"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
