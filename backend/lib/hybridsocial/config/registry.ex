defmodule Hybridsocial.Config.Registry do
  @moduledoc """
  Declares the runtime settings the generic admin settings API may write.

  `Config` values are stored untyped, so before this registry existed the
  `PUT /api/v1/admin/settings` endpoint wrote any key with whatever JSON type
  the client sent. That let a page save `"800"` where a reader expected `800`,
  and let any key be created. Each entry here fixes a key's type and bounds, so
  writes are allowlisted and cast before they reach the database.

  Entry fields:

    * `:type` - `:string`, `:integer`, `:number`, `:boolean`, or `{:enum, values}`
    * `:group` - the admin settings group the key belongs to (the future
      per-group permission maps onto this)
    * `:min` / `:max` - inclusive numeric bounds
    * `:max_length` - string length cap
    * `:secret` - write-only: never returned by the API, redacted in the audit log
    * `:advanced` - an expert tunable, shown behind an "Advanced" disclosure

  Keys that dedicated endpoints own (theme, email transport, translation,
  rules) are not listed: those endpoints do their own validation.
  """

  alias Hybridsocial.Premium.TierLimits

  @type entry :: %{
          required(:key) => String.t(),
          required(:type) => atom() | {:enum, [String.t()]},
          required(:group) => atom(),
          optional(:min) => number(),
          optional(:max) => number(),
          optional(:max_length) => pos_integer(),
          optional(:secret) => boolean(),
          optional(:advanced) => boolean()
        }

  @secret_string %{type: :string, secret: true, max_length: 2048}

  @static [
    # General
    %{key: "instance_name", type: :string, group: :general, max_length: 100},
    %{key: "instance_description", type: :string, group: :general, max_length: 5000},
    %{key: "contact_email", type: :string, group: :general, max_length: 254},

    # Sign-up & access
    %{
      key: "registration_mode",
      type: {:enum, ~w(open approval invite_only closed)},
      group: :access
    },
    %{
      key: "captcha_provider",
      type: {:enum, ~w(none turnstile hcaptcha recaptcha)},
      group: :access
    },
    %{key: "turnstile_site_key", type: :string, group: :access, max_length: 512},
    %{key: "hcaptcha_site_key", type: :string, group: :access, max_length: 512},
    %{key: "recaptcha_site_key", type: :string, group: :access, max_length: 512},
    Map.merge(@secret_string, %{key: "turnstile_secret_key", group: :access}),
    Map.merge(@secret_string, %{key: "hcaptcha_secret_key", group: :access}),
    Map.merge(@secret_string, %{key: "recaptcha_secret_key", group: :access}),
    %{key: "recaptcha_min_score", type: :number, group: :access, min: 0, max: 1},
    %{key: "pow_enabled", type: :boolean, group: :access},
    %{key: "pow_difficulty", type: :integer, group: :access, min: 8, max: 24, advanced: true},

    # Posting & accounts (0 = unlimited)
    %{key: "user_posts_per_minute", type: :integer, group: :posting, min: 0},
    %{key: "user_posts_per_hour", type: :integer, group: :posting, min: 0},
    %{key: "user_posts_per_day", type: :integer, group: :posting, min: 0},
    %{key: "bot_posts_per_minute", type: :integer, group: :posting, min: 0},
    %{key: "bot_posts_per_hour", type: :integer, group: :posting, min: 0},
    %{key: "bot_posts_per_day", type: :integer, group: :posting, min: 0},

    # Moderation & safety
    %{key: "report_email_notifications_enabled", type: :boolean, group: :moderation},
    %{key: "report_email_throttle_seconds", type: :integer, group: :moderation, min: 0},
    %{key: "takedown_purge_enabled", type: :boolean, group: :moderation},
    %{key: "takedown_reminder_lead_days", type: :integer, group: :moderation, min: 0},

    # Data retention (0 = keep forever, where the reader allows it)
    %{key: "takedown_retention_days", type: :integer, group: :retention, min: 1},
    %{key: "federation_delivery_retention_days", type: :integer, group: :retention, min: 0},

    # Monetization
    %{key: "tiers_enabled", type: :boolean, group: :monetization},
    %{key: "tiers_payment_configured", type: :boolean, group: :monetization},
    Map.merge(@secret_string, %{key: "stripe_secret_key", group: :monetization}),
    Map.merge(@secret_string, %{key: "stripe_webhook_secret", group: :monetization}),
    Map.merge(@secret_string, %{key: "paypal_secret", group: :monetization}),
    Map.merge(@secret_string, %{key: "crypto_api_key", group: :monetization}),
    Map.merge(@secret_string, %{key: "crypto_webhook_secret", group: :monetization}),

    # Media & storage
    Map.merge(@secret_string, %{key: "r2_access_key", group: :media}),
    Map.merge(@secret_string, %{key: "r2_secret_key", group: :media}),

    # Integrations
    Map.merge(@secret_string, %{key: "meilisearch_api_key", group: :integrations}),
    Map.merge(@secret_string, %{key: "giphy_api_key", group: :integrations}),
    Map.merge(@secret_string, %{key: "sms_api_key", group: :integrations})
  ]

  @static_by_key Map.new(@static, &{&1.key, &1})

  # Names that are secret whether or not they are registered, so a key added
  # later by a dedicated endpoint is still never echoed back by the generic API.
  @secret_name ~r/(secret|api_key|private_key|access_key|password|token)$/

  @markdown_levels ~w(none basic full full_embeds)

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

  # --- per-tier limits, derived from TierLimits defaults ---

  defp tier_entries do
    Enum.flat_map(TierLimits.tiers(), fn tier ->
      name = %{key: "tier_#{tier}_name", type: :string, group: :monetization, max_length: 50}
      [name | Enum.map(TierLimits.limit_keys(), &tier_limit_entry(tier, &1))]
    end)
  end

  defp tier_entry("tier_" <> rest = key) do
    Enum.find_value(TierLimits.tiers(), fn tier ->
      case String.split(rest, tier <> "_", parts: 2) do
        ["", "name"] ->
          %{key: key, type: :string, group: :monetization, max_length: 50}

        ["", limit] ->
          atom = Enum.find(TierLimits.limit_keys(), &(Atom.to_string(&1) == limit))
          atom && tier_limit_entry(tier, atom)

        _ ->
          nil
      end
    end)
  end

  defp tier_entry(_), do: nil

  defp tier_limit_entry(tier, :markdown) do
    %{key: "tier_#{tier}_markdown", type: {:enum, @markdown_levels}, group: :monetization}
  end

  defp tier_limit_entry(tier, limit) do
    key = "tier_#{tier}_#{limit}"

    case TierLimits.defaults()["free"][limit] do
      default when is_boolean(default) -> %{key: key, type: :boolean, group: :monetization}
      _ -> %{key: key, type: :integer, group: :monetization, min: 0}
    end
  end
end
