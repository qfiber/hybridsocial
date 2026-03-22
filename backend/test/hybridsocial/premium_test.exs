defmodule Hybridsocial.PremiumTest do
  use Hybridsocial.DataCase, async: true

  alias Hybridsocial.Premium

  defp create_user(handle, email) do
    {:ok, identity} =
      Hybridsocial.Accounts.register_user(%{
        "handle" => handle,
        "email" => email,
        "password" => "password123",
        "password_confirmation" => "password123"
      })

    identity
  end

  describe "apply_for_verification/3" do
    test "creates a verification request" do
      identity = create_user("verifyuser", "verify@test.com")

      assert {:ok, verification} =
               Premium.apply_for_verification(identity.id, "manual", %{"reason" => "test"})

      assert verification.type == "manual"
      assert verification.status == "pending"
      assert verification.metadata == %{"reason" => "test"}
    end

    test "rejects invalid verification type" do
      identity = create_user("verifyuser2", "verify2@test.com")

      assert {:error, changeset} =
               Premium.apply_for_verification(identity.id, "invalid")

      assert %{type: _} = errors_on(changeset)
    end
  end

  describe "approve_verification/2" do
    test "approves a pending verification" do
      identity = create_user("approveuser", "approve@test.com")
      {:ok, verification} = Premium.apply_for_verification(identity.id, "manual")

      assert {:ok, updated} = Premium.approve_verification(verification.id, "admin")
      assert updated.status == "approved"
      assert updated.verified_at != nil
    end

    test "returns error for non-existent verification" do
      assert {:error, :not_found} =
               Premium.approve_verification(Ecto.UUID.generate(), "admin")
    end
  end

  describe "reject_verification/2" do
    test "rejects a pending verification" do
      identity = create_user("rejectuser", "reject@test.com")
      {:ok, verification} = Premium.apply_for_verification(identity.id, "manual")

      assert {:ok, updated} = Premium.reject_verification(verification.id, "admin")
      assert updated.status == "rejected"
    end
  end

  describe "get_verification/1" do
    test "returns the latest verification" do
      identity = create_user("getverify", "getverify@test.com")
      {:ok, _} = Premium.apply_for_verification(identity.id, "manual")

      verification = Premium.get_verification(identity.id)
      assert verification.type == "manual"
    end

    test "returns nil when no verification exists" do
      identity = create_user("noverify", "noverify@test.com")
      assert Premium.get_verification(identity.id) == nil
    end
  end

  describe "verified?/1" do
    test "returns true when approved" do
      identity = create_user("verified1", "verified1@test.com")
      {:ok, verification} = Premium.apply_for_verification(identity.id, "manual")
      {:ok, _} = Premium.approve_verification(verification.id, "admin")

      assert Premium.verified?(identity.id) == true
    end

    test "returns false when pending" do
      identity = create_user("verified2", "verified2@test.com")
      {:ok, _} = Premium.apply_for_verification(identity.id, "manual")

      assert Premium.verified?(identity.id) == false
    end

    test "returns false when no verification" do
      identity = create_user("verified3", "verified3@test.com")
      assert Premium.verified?(identity.id) == false
    end
  end

  describe "create_subscription/2" do
    test "creates a subscription" do
      identity = create_user("subuser", "sub@test.com")

      assert {:ok, subscription} =
               Premium.create_subscription(identity.id, %{plan: "premium", payment_provider: "stripe"})

      assert subscription.plan == "premium"
      assert subscription.status == "active"
      assert subscription.payment_provider == "stripe"
      assert subscription.started_at != nil
    end
  end

  describe "get_subscription/1" do
    test "returns active subscription" do
      identity = create_user("getsub", "getsub@test.com")
      {:ok, _} = Premium.create_subscription(identity.id, %{plan: "premium"})

      subscription = Premium.get_subscription(identity.id)
      assert subscription.plan == "premium"
    end

    test "returns nil when no active subscription" do
      identity = create_user("nosub", "nosub@test.com")
      assert Premium.get_subscription(identity.id) == nil
    end
  end

  describe "premium?/1" do
    test "returns true for premium subscriber" do
      identity = create_user("premium1", "premium1@test.com")
      {:ok, _} = Premium.create_subscription(identity.id, %{plan: "premium"})

      assert Premium.premium?(identity.id) == true
    end

    test "returns false for free subscriber" do
      identity = create_user("free1", "free1@test.com")
      {:ok, _} = Premium.create_subscription(identity.id, %{plan: "free"})

      assert Premium.premium?(identity.id) == false
    end

    test "returns false with no subscription" do
      identity = create_user("nosub2", "nosub2@test.com")
      assert Premium.premium?(identity.id) == false
    end
  end

  describe "cancel_subscription/1" do
    test "cancels an active subscription" do
      identity = create_user("canceluser", "cancel@test.com")
      {:ok, _} = Premium.create_subscription(identity.id, %{plan: "premium"})

      assert {:ok, subscription} = Premium.cancel_subscription(identity.id)
      assert subscription.status == "cancelled"
      assert subscription.cancelled_at != nil
    end

    test "returns error when no active subscription" do
      identity = create_user("nocancel", "nocancel@test.com")
      assert {:error, :not_found} = Premium.cancel_subscription(identity.id)
    end
  end

  describe "feature_available?/2" do
    test "returns true for premium features when premium" do
      identity = create_user("feat1", "feat1@test.com")
      {:ok, _} = Premium.create_subscription(identity.id, %{plan: "premium"})

      assert Premium.feature_available?(identity.id, :markdown) == true
      assert Premium.feature_available?(identity.id, :hd_video) == true
    end

    test "returns false for premium features when free" do
      identity = create_user("feat2", "feat2@test.com")

      assert Premium.feature_available?(identity.id, :markdown) == false
      assert Premium.feature_available?(identity.id, :hd_video) == false
    end

    test "returns false for unknown features" do
      identity = create_user("feat3", "feat3@test.com")
      assert Premium.feature_available?(identity.id, :unknown_feature) == false
    end
  end
end
