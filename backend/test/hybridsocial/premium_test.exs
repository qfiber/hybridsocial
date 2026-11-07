defmodule Hybridsocial.PremiumTest do
  use Hybridsocial.DataCase, async: true

  alias Hybridsocial.Accounts.Identity
  alias Hybridsocial.Premium
  alias Hybridsocial.Repo

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
    test "approves the request and verifies the account, without a paid tier" do
      admin = create_user("approveadmin", "approveadmin@test.com")
      identity = create_user("approveuser", "approve@test.com")
      {:ok, verification} = Premium.apply_for_verification(identity.id, "manual")

      assert {:ok, updated} = Premium.approve_verification(verification.id, admin.id)
      assert updated.status == "approved"
      assert updated.verified_at != nil

      account = Repo.get!(Identity, identity.id)
      assert account.verified_at
      assert account.verified_by_id == admin.id
      assert account.verification_tier == "free"
      assert Identity.verified?(account)
    end

    test "a decided request can't be approved again" do
      admin = create_user("approveadmin2", "approveadmin2@test.com")
      identity = create_user("approveuser2", "approve2@test.com")
      {:ok, verification} = Premium.apply_for_verification(identity.id, "manual")
      {:ok, _} = Premium.reject_verification(verification.id, admin.id)

      assert {:error, :not_pending} = Premium.approve_verification(verification.id, admin.id)
      refute Repo.get!(Identity, identity.id).verified_at
    end

    test "returns error for non-existent verification" do
      assert {:error, :not_found} =
               Premium.approve_verification(Ecto.UUID.generate(), Ecto.UUID.generate())
    end
  end

  describe "applying while verified or waiting" do
    test "a second request while one is pending is refused" do
      identity = create_user("dupapply", "dupapply@test.com")
      {:ok, _} = Premium.apply_for_verification(identity.id, "manual")

      assert {:error, :already_pending} = Premium.apply_for_verification(identity.id, "manual")
    end

    test "a verified account can't apply" do
      admin = create_user("applyadmin", "applyadmin@test.com")
      identity = create_user("verifiedapply", "verifiedapply@test.com")
      {:ok, _} = Premium.verify_identity(identity.id, admin.id)

      assert {:error, :already_verified} = Premium.apply_for_verification(identity.id, "manual")
    end
  end

  describe "peer vouches" do
    test "don't verify the account on their own, however many there are" do
      identity = create_user("vouched", "vouched@test.com")
      {:ok, verification} = Premium.apply_for_verification(identity.id, "peer_vouch")

      for n <- 1..4 do
        voucher = create_user("voucher#{n}", "voucher#{n}@test.com")
        assert {:ok, _} = Premium.vouch_for(verification.id, voucher.id)
      end

      assert Repo.get!(Premium.Verification, verification.id).status == "pending"
      refute Repo.get!(Identity, identity.id).verified_at
    end
  end

  describe "revoke_verification/1" do
    test "removes staff verification and leaves a paid tier alone" do
      admin = create_user("revokeadmin", "revokeadmin@test.com")
      identity = create_user("revokeuser", "revoke@test.com")

      identity
      |> Ecto.Changeset.change(verification_tier: "verified_creator")
      |> Repo.update!()

      {:ok, _} = Premium.verify_identity(identity.id, admin.id)
      assert {:ok, revoked} = Premium.revoke_verification(identity.id)

      assert revoked.verified_at == nil
      assert revoked.verified_by_id == nil
      assert revoked.verification_tier == "verified_creator"
      refute Premium.verified?(identity.id)
    end

    test "an unverified account is an error" do
      identity = create_user("neververified", "neververified@test.com")
      assert {:error, :not_verified} = Premium.revoke_verification(identity.id)
    end
  end

  describe "reject_verification/2" do
    test "rejects a pending verification" do
      identity = create_user("rejectuser", "reject@test.com")
      {:ok, verification} = Premium.apply_for_verification(identity.id, "manual")

      assert {:ok, updated} = Premium.reject_verification(verification.id, "admin")
      assert updated.status == "rejected"
      assert updated.rejection_reason == nil
    end

    test "records the rejection reason when given" do
      identity = create_user("rejectuser2", "reject2@test.com")
      {:ok, verification} = Premium.apply_for_verification(identity.id, "manual")

      assert {:ok, updated} =
               Premium.reject_verification(verification.id, "admin", "Insufficient evidence")

      assert updated.status == "rejected"
      assert updated.rejection_reason == "Insufficient evidence"
    end

    test "treats a blank reason as no reason" do
      identity = create_user("rejectuser3", "reject3@test.com")
      {:ok, verification} = Premium.apply_for_verification(identity.id, "manual")

      assert {:ok, updated} = Premium.reject_verification(verification.id, "admin", "   ")
      assert updated.rejection_reason == nil
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
      {:ok, _} = Premium.approve_verification(verification.id, identity.id)

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
               Premium.create_subscription(identity.id, %{
                 plan: "premium",
                 payment_provider: "stripe"
               })

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
