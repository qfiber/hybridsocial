defmodule HybridsocialWeb.Api.V1.AdminVerificationTest do
  # Staff verification of accounts, separate from the paid tiers (#168).
  use HybridsocialWeb.ConnCase, async: true

  alias Hybridsocial.Accounts.Identity
  alias Hybridsocial.Moderation
  alias Hybridsocial.Premium
  alias Hybridsocial.Repo

  setup %{conn: conn} do
    admin = create_admin("verif_admin")
    user = create_user("verif_user")
    %{conn: conn, admin: admin, admin_conn: admin_conn(conn, admin), user: user}
  end

  defp account_json(conn, identity) do
    conn |> get("/api/v1/accounts/#{identity.id}") |> json_response(200)
  end

  describe "approving a request" do
    test "verifies the account: the badge shows, and no tier is granted",
         %{conn: conn, admin_conn: admin_conn, user: user} do
      {:ok, request} = Premium.apply_for_verification(user.id, "manual")

      assert %{"data" => %{"status" => "approved"}} =
               admin_conn
               |> post("/api/v1/admin/verifications/#{request.id}/approve")
               |> json_response(200)

      account = account_json(conn, user)
      assert account["is_verified"] == true
      assert account["verification_tier"] == "free"

      assert Repo.get_by(Moderation.AuditLog, action: "account.verified", target_id: user.id)
    end

    # A moderator can see requests (`users.view`) but verifying changes the
    # account, which needs `users.manage`.
    test "needs users.manage, not just users.view", %{conn: conn, user: user} do
      moderator = create_moderator("verif_mod")
      {:ok, request} = Premium.apply_for_verification(user.id, "manual")
      mod_conn = admin_conn(conn, moderator)

      assert mod_conn |> get("/api/v1/admin/verifications") |> json_response(200)

      for action <- ["approve", "reject"] do
        response = post(mod_conn, "/api/v1/admin/verifications/#{request.id}/#{action}")
        assert response.status in [401, 403]
      end

      refute Repo.get!(Identity, user.id).verified_at
    end

    test "an already decided request is a conflict", %{admin_conn: admin_conn, user: user} do
      {:ok, request} = Premium.apply_for_verification(user.id, "manual")

      assert admin_conn
             |> post("/api/v1/admin/verifications/#{request.id}/reject")
             |> json_response(200)

      assert %{"error" => "verification.not_pending"} =
               admin_conn
               |> post("/api/v1/admin/verifications/#{request.id}/approve")
               |> json_response(409)
    end
  end

  describe "verifying and unverifying directly" do
    test "staff can verify an account that never applied",
         %{conn: conn, admin_conn: admin_conn, user: user} do
      assert %{"data" => %{"is_verified" => true}} =
               admin_conn
               |> post("/api/v1/admin/users/#{user.id}/verification")
               |> json_response(200)

      assert account_json(conn, user)["is_verified"] == true

      # The account's own status page says so, though there's no request.
      assert %{"status" => "approved"} =
               conn |> auth_conn(user) |> get("/api/v1/verification/status") |> json_response(200)
    end

    test "removing it with a reason sends a notice, and an approved appeal restores it",
         %{conn: conn, admin: admin, admin_conn: admin_conn, user: user} do
      {:ok, _} = Premium.verify_identity(user.id, admin.id)

      assert %{"data" => %{"is_verified" => false}} =
               admin_conn
               |> delete("/api/v1/admin/users/#{user.id}/verification", %{
                 "reason" => "impersonation"
               })
               |> json_response(200)

      assert account_json(conn, user)["is_verified"] == false

      takedown =
        Repo.get_by!(Moderation.Takedown, target_id: user.id, target_type: "account_badge")

      assert takedown.reason == "impersonation"

      {:ok, appeal} = Moderation.create_takedown_appeal(user.id, takedown.id, "it's really me")
      {:ok, _} = Moderation.approve_appeal(appeal.id, admin.id)

      assert Repo.get!(Identity, user.id).verified_at
    end

    test "removing it without a reason sends no notice", %{
      admin: admin,
      admin_conn: admin_conn,
      user: user
    } do
      {:ok, _} = Premium.verify_identity(user.id, admin.id)

      assert admin_conn
             |> delete("/api/v1/admin/users/#{user.id}/verification")
             |> json_response(200)

      refute Repo.get_by(Moderation.Takedown, target_id: user.id)
    end

    test "removing it from an unverified account is a conflict", %{
      admin_conn: admin_conn,
      user: user
    } do
      assert %{"error" => "verification.not_verified"} =
               admin_conn
               |> delete("/api/v1/admin/users/#{user.id}/verification")
               |> json_response(409)
    end

    test "a regular user can do neither", %{conn: conn, user: user} do
      other = create_user("verif_other")
      user_conn = auth_conn(conn, other)

      assert post(user_conn, "/api/v1/admin/users/#{user.id}/verification").status in [401, 403]
      assert delete(user_conn, "/api/v1/admin/users/#{user.id}/verification").status in [401, 403]
      refute Repo.get!(Identity, user.id).verified_at
    end
  end

  describe "applying" do
    test "a second request while one is waiting is a conflict", %{conn: conn, user: user} do
      user_conn = auth_conn(conn, user)

      assert user_conn
             |> post("/api/v1/verification/apply", %{"type" => "manual"})
             |> json_response(201)

      assert %{"error" => "verification.already_pending"} =
               user_conn
               |> post("/api/v1/verification/apply", %{"type" => "manual"})
               |> json_response(409)
    end
  end

  describe "the display-name lock" do
    test "applies to a staff-verified account", %{admin: admin, user: user} do
      {:ok, verified} = Premium.verify_identity(user.id, admin.id)

      assert {:error, changeset} =
               Hybridsocial.Accounts.update_identity(verified, %{"display_name" => "Someone Else"})

      assert %{display_name: _} = Hybridsocial.DataCase.errors_on(changeset)
    end
  end
end
