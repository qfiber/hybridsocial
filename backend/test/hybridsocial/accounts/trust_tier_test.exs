defmodule Hybridsocial.Accounts.TrustTierTest do
  # async: false — writes runtime config to the shared Config.Store.
  use Hybridsocial.DataCase, async: false

  alias Hybridsocial.Config
  alias Hybridsocial.Social.Posts

  setup do
    start_supervised!(Hybridsocial.Config.Store)
    :ok
  end

  test "an account on a paid tier skips the new-account gates" do
    Config.set("tiers_enabled", true)

    identity =
      create_user("paidnew")
      |> Ecto.Changeset.change(verification_tier: "verified_starter")
      |> Hybridsocial.Repo.update!()

    assert {:ok, _} =
             Posts.create_post(identity.id, %{"content" => "https://x.example"}, identity)
  end

  test "with tiers off, nobody counts as paid" do
    Config.set("tiers_enabled", false)

    identity =
      create_user("notpaid")
      |> Ecto.Changeset.change(verification_tier: "verified_pro")
      |> Hybridsocial.Repo.update!()

    assert {:error, :trust_links_not_allowed} =
             Posts.create_post(identity.id, %{"content" => "https://x.example"}, identity)
  end

  test "the link gate can be switched off" do
    Config.set("trust_gate_links", false)
    identity = create_user("gateoff")

    assert {:ok, _} =
             Posts.create_post(identity.id, %{"content" => "https://x.example"}, identity)
  end

  test "thresholds come from settings" do
    Config.set("trust_level_1_hours", 0)
    Config.set("trust_level_1_posts", 0)
    identity = create_user("instant")

    assert {:ok, _} =
             Posts.create_post(identity.id, %{"content" => "https://x.example"}, identity)
  end
end
