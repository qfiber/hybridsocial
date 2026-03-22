defmodule HybridsocialWeb.Api.V1.GroupControllerTest do
  use HybridsocialWeb.ConnCase, async: true

  alias Hybridsocial.Groups

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

  defp login(conn, email) do
    {:ok, tokens} = Hybridsocial.Auth.login(email, "password123")
    put_req_header(conn, "authorization", "Bearer #{tokens.access_token}")
  end

  defp setup_user(%{conn: conn}) do
    identity = create_user("testuser", "testuser@test.com")
    conn = login(conn, "testuser@test.com")
    %{conn: conn, identity: identity}
  end

  # ---------------------------------------------------------------------------
  # Group CRUD
  # ---------------------------------------------------------------------------

  describe "POST /api/v1/groups" do
    setup :setup_user

    test "creates a group", %{conn: conn} do
      conn =
        post(conn, "/api/v1/groups", %{
          "name" => "My Group",
          "description" => "A great group"
        })

      response = json_response(conn, 201)
      assert response["name"] == "My Group"
      assert response["description"] == "A great group"
      assert response["member_count"] == 1
      assert response["id"] != nil
    end

    test "returns errors for missing name", %{conn: conn} do
      conn = post(conn, "/api/v1/groups", %{})
      response = json_response(conn, 422)
      assert response["error"] == "validation.failed"
    end

    test "requires authentication" do
      conn = build_conn()
      conn = post(conn, "/api/v1/groups", %{"name" => "Group"})
      assert json_response(conn, 401)
    end
  end

  describe "GET /api/v1/groups" do
    setup :setup_user

    test "lists groups", %{conn: conn, identity: identity} do
      {:ok, _} = Groups.create_group(identity.id, %{"name" => "Group 1"})
      {:ok, _} = Groups.create_group(identity.id, %{"name" => "Group 2"})

      conn = get(conn, "/api/v1/groups")
      response = json_response(conn, 200)
      assert length(response) == 2
    end

    test "searches groups", %{conn: conn, identity: identity} do
      {:ok, _} = Groups.create_group(identity.id, %{"name" => "Elixir Fans"})
      {:ok, _} = Groups.create_group(identity.id, %{"name" => "Sports Club"})

      conn = get(conn, "/api/v1/groups", %{"q" => "elixir"})
      response = json_response(conn, 200)
      assert length(response) == 1
      assert hd(response)["name"] == "Elixir Fans"
    end
  end

  describe "GET /api/v1/groups/:id" do
    setup :setup_user

    test "shows a group", %{conn: conn, identity: identity} do
      {:ok, group} = Groups.create_group(identity.id, %{"name" => "Show Me"})

      conn = get(conn, "/api/v1/groups/#{group.id}")
      response = json_response(conn, 200)
      assert response["name"] == "Show Me"
    end

    test "returns 404 for missing group", %{conn: conn} do
      fake_id = Ecto.UUID.generate()
      conn = get(conn, "/api/v1/groups/#{fake_id}")
      assert json_response(conn, 404)["error"] == "group.not_found"
    end
  end

  describe "PATCH /api/v1/groups/:id" do
    setup :setup_user

    test "updates a group", %{conn: conn, identity: identity} do
      {:ok, group} = Groups.create_group(identity.id, %{"name" => "Original"})

      conn = patch(conn, "/api/v1/groups/#{group.id}", %{"name" => "Updated"})
      response = json_response(conn, 200)
      assert response["name"] == "Updated"
    end

    test "rejects update from non-admin", %{conn: conn, identity: identity} do
      other = create_user("other", "other@test.com")
      {:ok, group} = Groups.create_group(other.id, %{"name" => "Not Yours"})
      {:ok, _} = Groups.join_group(group.id, identity.id)

      conn = patch(conn, "/api/v1/groups/#{group.id}", %{"name" => "Hacked"})
      assert json_response(conn, 403)["error"] == "group.forbidden"
    end
  end

  describe "DELETE /api/v1/groups/:id" do
    setup :setup_user

    test "deletes a group", %{conn: conn, identity: identity} do
      {:ok, group} = Groups.create_group(identity.id, %{"name" => "Doomed"})

      conn = delete(conn, "/api/v1/groups/#{group.id}")
      assert json_response(conn, 200)["message"] == "group.deleted"
    end

    test "non-owner cannot delete", %{conn: conn, identity: identity} do
      other = create_user("other2", "other2@test.com")
      {:ok, group} = Groups.create_group(other.id, %{"name" => "Safe"})
      {:ok, _} = Groups.join_group(group.id, identity.id)

      conn = delete(conn, "/api/v1/groups/#{group.id}")
      assert json_response(conn, 403)["error"] == "group.forbidden"
    end
  end

  # ---------------------------------------------------------------------------
  # Membership
  # ---------------------------------------------------------------------------

  describe "POST /api/v1/groups/:id/join" do
    setup :setup_user

    test "joins an open group", %{conn: conn} do
      other = create_user("groupowner", "groupowner@test.com")
      {:ok, group} = Groups.create_group(other.id, %{"name" => "Open Group"})

      conn = post(conn, "/api/v1/groups/#{group.id}/join")
      response = json_response(conn, 200)
      assert response["status"] == "approved"
    end

    test "returns 404 for non-existent group", %{conn: conn} do
      fake_id = Ecto.UUID.generate()
      conn = post(conn, "/api/v1/groups/#{fake_id}/join")
      assert json_response(conn, 404)
    end
  end

  describe "POST /api/v1/groups/:id/leave" do
    setup :setup_user

    test "leaves a group", %{conn: conn} do
      other = create_user("leaveowner", "leaveowner@test.com")
      {:ok, group} = Groups.create_group(other.id, %{"name" => "Leave Me"})
      # Use the context identity (testuser) to join, then leave
      identity = Hybridsocial.Accounts.get_identity_by_handle("testuser")
      {:ok, _} = Groups.join_group(group.id, identity.id)

      conn = post(conn, "/api/v1/groups/#{group.id}/leave")
      assert json_response(conn, 200)["message"] == "group.left"
    end
  end

  describe "GET /api/v1/groups/:id/members" do
    setup :setup_user

    test "lists members", %{conn: conn, identity: identity} do
      {:ok, group} = Groups.create_group(identity.id, %{"name" => "Group"})

      conn = get(conn, "/api/v1/groups/#{group.id}/members")
      response = json_response(conn, 200)
      assert length(response) == 1
    end
  end

  # ---------------------------------------------------------------------------
  # Invites
  # ---------------------------------------------------------------------------

  describe "POST /api/v1/groups/:id/invite" do
    setup :setup_user

    test "invites a user", %{conn: conn, identity: identity} do
      {:ok, group} = Groups.create_group(identity.id, %{"name" => "Group"})
      other = create_user("invited", "invited@test.com")

      conn = post(conn, "/api/v1/groups/#{group.id}/invite", %{"invited_id" => other.id})
      response = json_response(conn, 201)
      assert response["status"] == "pending"
      assert response["invited_id"] == other.id
    end
  end

  # ---------------------------------------------------------------------------
  # Applications
  # ---------------------------------------------------------------------------

  describe "applications endpoints" do
    setup :setup_user

    test "lists applications", %{conn: conn, identity: identity} do
      {:ok, group} = Groups.create_group(identity.id, %{"name" => "Group"})
      other = create_user("applicant", "applicant@test.com")
      {:ok, _} = Groups.apply_to_group(group.id, other.id, %{"reason" => "please"})

      conn = get(conn, "/api/v1/groups/#{group.id}/applications")
      response = json_response(conn, 200)
      assert length(response) == 1
    end

    test "approves application", %{conn: conn, identity: identity} do
      {:ok, group} = Groups.create_group(identity.id, %{"name" => "Group"})
      other = create_user("applicant2", "applicant2@test.com")
      {:ok, application} = Groups.apply_to_group(group.id, other.id, %{})

      conn = post(conn, "/api/v1/groups/#{group.id}/applications/#{application.id}/approve")
      response = json_response(conn, 200)
      assert response["status"] == "approved"
    end

    test "rejects application", %{conn: conn, identity: identity} do
      {:ok, group} = Groups.create_group(identity.id, %{"name" => "Group"})
      other = create_user("applicant3", "applicant3@test.com")
      {:ok, application} = Groups.apply_to_group(group.id, other.id, %{})

      conn = post(conn, "/api/v1/groups/#{group.id}/applications/#{application.id}/reject")
      response = json_response(conn, 200)
      assert response["status"] == "rejected"
    end
  end

  # ---------------------------------------------------------------------------
  # Member management
  # ---------------------------------------------------------------------------

  describe "PATCH /api/v1/groups/:id/members/:mid" do
    setup :setup_user

    test "updates member role", %{conn: conn, identity: identity} do
      {:ok, group} = Groups.create_group(identity.id, %{"name" => "Group"})
      other = create_user("member1", "member1@test.com")
      {:ok, member} = Groups.join_group(group.id, other.id)

      conn = patch(conn, "/api/v1/groups/#{group.id}/members/#{member.id}", %{"role" => "moderator"})
      response = json_response(conn, 200)
      assert response["role"] == "moderator"
    end
  end

  describe "DELETE /api/v1/groups/:id/members/:mid" do
    setup :setup_user

    test "bans a member", %{conn: conn, identity: identity} do
      {:ok, group} = Groups.create_group(identity.id, %{"name" => "Group"})
      other = create_user("banned1", "banned1@test.com")
      {:ok, member} = Groups.join_group(group.id, other.id)

      conn = delete(conn, "/api/v1/groups/#{group.id}/members/#{member.id}")
      response = json_response(conn, 200)
      assert response["status"] == "banned"
    end
  end

  # ---------------------------------------------------------------------------
  # Screening config
  # ---------------------------------------------------------------------------

  describe "screening endpoints" do
    setup :setup_user

    test "get default screening config", %{conn: conn, identity: identity} do
      {:ok, group} = Groups.create_group(identity.id, %{"name" => "Group"})

      conn = get(conn, "/api/v1/groups/#{group.id}/screening")
      response = json_response(conn, 200)
      assert response["require_profile_image"] == false
      assert response["min_account_age_days"] == 0
    end

    test "update screening config", %{conn: conn, identity: identity} do
      {:ok, group} = Groups.create_group(identity.id, %{"name" => "Group"})

      conn =
        patch(conn, "/api/v1/groups/#{group.id}/screening", %{
          "require_profile_image" => true,
          "min_account_age_days" => 30
        })

      response = json_response(conn, 200)
      assert response["require_profile_image"] == true
      assert response["min_account_age_days"] == 30
    end
  end
end
