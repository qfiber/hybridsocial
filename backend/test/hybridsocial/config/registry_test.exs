defmodule Hybridsocial.Config.RegistryTest do
  use ExUnit.Case, async: true

  alias Hybridsocial.Config.Registry

  describe "cast/2" do
    test "rejects keys that aren't registered" do
      assert Registry.cast("not_a_real_setting", 1) == {:error, :unknown_key}
    end

    test "types integers, including the strings forms used to send" do
      assert Registry.cast("pow_difficulty", 16) == {:ok, 16}
      assert Registry.cast("pow_difficulty", "18") == {:ok, 18}
      assert Registry.cast("pow_difficulty", 20.0) == {:ok, 20}
      assert Registry.cast("pow_difficulty", "18abc") == {:error, :invalid_integer}
      assert Registry.cast("pow_difficulty", 16.5) == {:error, :invalid_integer}
    end

    test "enforces numeric bounds" do
      assert Registry.cast("pow_difficulty", 4) == {:error, :below_minimum}
      assert Registry.cast("pow_difficulty", 40) == {:error, :above_maximum}
      assert Registry.cast("recaptcha_min_score", "0.7") == {:ok, 0.7}
      assert Registry.cast("recaptcha_min_score", 2) == {:error, :above_maximum}
      assert Registry.cast("user_posts_per_hour", -1) == {:error, :below_minimum}
    end

    test "types booleans from JSON or string form" do
      assert Registry.cast("pow_enabled", true) == {:ok, true}
      assert Registry.cast("pow_enabled", "false") == {:ok, false}
      assert Registry.cast("pow_enabled", "yes") == {:error, :invalid_boolean}
    end

    test "limits enums to their declared values" do
      assert Registry.cast("registration_mode", "invite_only") == {:ok, "invite_only"}
      assert Registry.cast("registration_mode", "secret") == {:error, :invalid_option}
      assert Registry.cast("captcha_provider", 1) == {:error, :invalid_option}
    end

    test "caps string length" do
      assert {:ok, _} = Registry.cast("instance_name", "Bassam")
      assert Registry.cast("instance_name", String.duplicate("a", 101)) == {:error, :too_long}
      assert Registry.cast("instance_name", 42) == {:error, :invalid_string}
    end

    # The Tiers page sends every field as a string; the post changeset then
    # used "800" as a length limit. Casting types them by the tier defaults.
    test "types per-tier limits from the TierLimits defaults" do
      assert Registry.cast("tier_free_char_limit", "800") == {:ok, 800}
      assert Registry.cast("tier_verified_pro_scheduled_posts", "true") == {:ok, true}
      assert Registry.cast("tier_verified_creator_markdown", "full") == {:ok, "full"}
      assert Registry.cast("tier_verified_creator_markdown", "html") == {:error, :invalid_option}
      assert Registry.cast("tier_verified_starter_name", "Basic") == {:ok, "Basic"}
      assert Registry.cast("tier_free_not_a_limit", 1) == {:error, :unknown_key}
      assert Registry.cast("tier_platinum_char_limit", 1) == {:error, :unknown_key}
    end
  end

  describe "secret?/1" do
    test "covers registered secrets and secret-looking names that aren't registered" do
      assert Registry.secret?("stripe_secret_key")
      assert Registry.secret?("r2_access_key")
      assert Registry.secret?("some_future_api_key")
      assert Registry.secret?("vapid_private_key")
      refute Registry.secret?("turnstile_site_key")
      refute Registry.secret?("instance_name")
    end
  end

  describe "normalize/2" do
    test "types registered values and leaves the rest alone" do
      assert Registry.normalize("tier_free_char_limit", "800") == 800
      assert Registry.normalize("pow_enabled", "true") == true
      assert Registry.normalize("pow_difficulty", "garbage") == "garbage"
      assert Registry.normalize("unregistered_key", "800") == "800"
    end
  end

  test "every registered key casts its own example value without error" do
    for entry <- Registry.entries() do
      sample =
        case entry.type do
          :boolean -> true
          :integer -> Map.get(entry, :min, 0)
          :number -> Map.get(entry, :min, 0)
          :string -> ""
          {:enum, [first | _]} -> first
        end

      assert {:ok, _} = Registry.cast(entry.key, sample),
             "#{entry.key} rejected #{inspect(sample)}"
    end
  end
end
