defmodule HybridsocialWeb.Api.V1.ConversationControllerTest do
  use HybridsocialWeb.ConnCase, async: false

  alias Hybridsocial.Auth.Token
  alias Hybridsocial.Messaging

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp create_user(handle, email) do
    {:ok, identity} =
      Hybridsocial.Accounts.register_user(%{
        "handle" => handle,
        "email" => email,
        "password" => "Password123!!",
        "password_confirmation" => "Password123!!"
      })

    identity
  end

  defp authenticate(conn, identity) do
    {:ok, access_token, _claims} = Token.generate_access_token(identity.id)

    conn
    |> put_req_header("authorization", "Bearer #{access_token}")
  end

  # ---------------------------------------------------------------------------
  # Conversations
  # ---------------------------------------------------------------------------

  describe "GET /api/v1/conversations" do
    test "requires authentication", %{conn: conn} do
      conn = get(conn, "/api/v1/conversations")
      assert json_response(conn, 401)
    end

    test "returns empty list when no conversations", %{conn: conn} do
      alice = create_user("cc_alice", "cc_alice@example.com")

      conn =
        conn
        |> authenticate(alice)
        |> get("/api/v1/conversations")

      assert json_response(conn, 200) == []
    end

    test "returns user's conversations", %{conn: conn} do
      alice = create_user("cc_alice2", "cc_alice2@example.com")
      bob = create_user("cc_bob2", "cc_bob2@example.com")

      {:ok, _} = Messaging.find_or_create_direct(alice.id, bob.id)

      conn =
        conn
        |> authenticate(alice)
        |> get("/api/v1/conversations")

      response = json_response(conn, 200)
      assert length(response) == 1
      assert hd(response)["type"] == "direct"
    end
  end

  describe "POST /api/v1/conversations" do
    test "creates a direct conversation", %{conn: conn} do
      alice = create_user("cc_create", "cc_create@example.com")
      bob = create_user("cc_create2", "cc_create2@example.com")

      conn =
        conn
        |> authenticate(alice)
        |> post("/api/v1/conversations", %{"recipient_ids" => [bob.id]})

      response = json_response(conn, 201)
      assert response["type"] == "direct"
      assert response["id"] != nil
    end

    test "creates a group DM", %{conn: conn} do
      alice = create_user("cc_grp", "cc_grp@example.com")
      bob = create_user("cc_grp2", "cc_grp2@example.com")
      carol = create_user("cc_grp3", "cc_grp3@example.com")

      conn =
        conn
        |> authenticate(alice)
        |> post("/api/v1/conversations", %{"recipient_ids" => [bob.id, carol.id]})

      response = json_response(conn, 201)
      assert response["type"] == "group_dm"
    end

    test "returns error for self-messaging", %{conn: conn} do
      alice = create_user("cc_self", "cc_self@example.com")

      conn =
        conn
        |> authenticate(alice)
        |> post("/api/v1/conversations", %{"recipient_ids" => [alice.id]})

      assert json_response(conn, 422)["error"] == "dm.cannot_message_self"
    end

    test "returns forbidden when DM not allowed", %{conn: conn} do
      alice = create_user("cc_block", "cc_block@example.com")
      bob = create_user("cc_block2", "cc_block2@example.com")

      {:ok, _} = Messaging.update_dm_preferences(bob.id, %{"allow_dms_from" => "nobody"})

      conn =
        conn
        |> authenticate(alice)
        |> post("/api/v1/conversations", %{"recipient_ids" => [bob.id]})

      assert json_response(conn, 403)["error"] == "dm.not_allowed"
    end
  end

  describe "GET /api/v1/conversations/:id" do
    test "shows a conversation", %{conn: conn} do
      alice = create_user("cc_show", "cc_show@example.com")
      bob = create_user("cc_show2", "cc_show2@example.com")

      {:ok, conv} = Messaging.find_or_create_direct(alice.id, bob.id)

      conn =
        conn
        |> authenticate(alice)
        |> get("/api/v1/conversations/#{conv.id}")

      response = json_response(conn, 200)
      assert response["id"] == conv.id
      assert response["type"] == "direct"
    end

    test "returns 404 for non-participant", %{conn: conn} do
      alice = create_user("cc_show3", "cc_show3@example.com")
      bob = create_user("cc_show4", "cc_show4@example.com")
      carol = create_user("cc_show5", "cc_show5@example.com")

      {:ok, conv} = Messaging.find_or_create_direct(alice.id, bob.id)

      conn =
        conn
        |> authenticate(carol)
        |> get("/api/v1/conversations/#{conv.id}")

      assert json_response(conn, 404)
    end
  end

  # ---------------------------------------------------------------------------
  # Messages
  # ---------------------------------------------------------------------------

  describe "POST /api/v1/conversations/:id/messages" do
    test "sends a message", %{conn: conn} do
      alice = create_user("cc_msg", "cc_msg@example.com")
      bob = create_user("cc_msg2", "cc_msg2@example.com")

      {:ok, conv} = Messaging.find_or_create_direct(alice.id, bob.id)

      conn =
        conn
        |> authenticate(alice)
        |> post("/api/v1/conversations/#{conv.id}/messages", %{"content" => "Hello Bob!"})

      response = json_response(conn, 201)
      assert response["content"] == "Hello Bob!"
      assert response["sender"]["id"] == alice.id
    end

    test "returns 404 for non-participant", %{conn: conn} do
      alice = create_user("cc_msg3", "cc_msg3@example.com")
      bob = create_user("cc_msg4", "cc_msg4@example.com")
      carol = create_user("cc_msg5", "cc_msg5@example.com")

      {:ok, conv} = Messaging.find_or_create_direct(alice.id, bob.id)

      conn =
        conn
        |> authenticate(carol)
        |> post("/api/v1/conversations/#{conv.id}/messages", %{"content" => "Hi!"})

      assert json_response(conn, 404)
    end
  end

  describe "GET /api/v1/conversations/:id/messages" do
    test "returns messages", %{conn: conn} do
      alice = create_user("cc_gm", "cc_gm@example.com")
      bob = create_user("cc_gm2", "cc_gm2@example.com")

      {:ok, conv} = Messaging.find_or_create_direct(alice.id, bob.id)
      {:ok, _} = Messaging.send_message(conv.id, alice.id, %{"content" => "Hello!"})
      {:ok, _} = Messaging.send_message(conv.id, bob.id, %{"content" => "Hi there!"})

      conn =
        conn
        |> authenticate(alice)
        |> get("/api/v1/conversations/#{conv.id}/messages")

      response = json_response(conn, 200)
      assert length(response) == 2
    end
  end

  describe "PUT /api/v1/conversations/:id/messages/:mid" do
    test "edits a message", %{conn: conn} do
      alice = create_user("cc_em", "cc_em@example.com")
      bob = create_user("cc_em2", "cc_em2@example.com")

      {:ok, conv} = Messaging.find_or_create_direct(alice.id, bob.id)
      {:ok, msg} = Messaging.send_message(conv.id, alice.id, %{"content" => "Hello!"})

      conn =
        conn
        |> authenticate(alice)
        |> put("/api/v1/conversations/#{conv.id}/messages/#{msg.id}", %{"content" => "Updated!"})

      response = json_response(conn, 200)
      assert response["content"] == "Updated!"
      assert response["edited_at"] != nil
    end

    test "returns forbidden when editing another's message", %{conn: conn} do
      alice = create_user("cc_em3", "cc_em3@example.com")
      bob = create_user("cc_em4", "cc_em4@example.com")

      {:ok, conv} = Messaging.find_or_create_direct(alice.id, bob.id)
      {:ok, msg} = Messaging.send_message(conv.id, alice.id, %{"content" => "Hello!"})

      conn =
        conn
        |> authenticate(bob)
        |> put("/api/v1/conversations/#{conv.id}/messages/#{msg.id}", %{"content" => "Hacked!"})

      assert json_response(conn, 403)["error"] == "message.forbidden"
    end
  end

  describe "DELETE /api/v1/conversations/:id/messages/:mid" do
    test "deletes a message", %{conn: conn} do
      alice = create_user("cc_dm", "cc_dm@example.com")
      bob = create_user("cc_dm2", "cc_dm2@example.com")

      {:ok, conv} = Messaging.find_or_create_direct(alice.id, bob.id)
      {:ok, msg} = Messaging.send_message(conv.id, alice.id, %{"content" => "Hello!"})

      conn =
        conn
        |> authenticate(alice)
        |> delete("/api/v1/conversations/#{conv.id}/messages/#{msg.id}")

      assert json_response(conn, 200)["message"] == "message.deleted"
    end

    test "returns forbidden when deleting another's message", %{conn: conn} do
      alice = create_user("cc_dm3", "cc_dm3@example.com")
      bob = create_user("cc_dm4", "cc_dm4@example.com")

      {:ok, conv} = Messaging.find_or_create_direct(alice.id, bob.id)
      {:ok, msg} = Messaging.send_message(conv.id, alice.id, %{"content" => "Hello!"})

      conn =
        conn
        |> authenticate(bob)
        |> delete("/api/v1/conversations/#{conv.id}/messages/#{msg.id}")

      assert json_response(conn, 403)["error"] == "message.forbidden"
    end
  end

  # ---------------------------------------------------------------------------
  # Mark Read
  # ---------------------------------------------------------------------------

  describe "POST /api/v1/conversations/:id/read" do
    test "marks conversation as read", %{conn: conn} do
      alice = create_user("cc_mr", "cc_mr@example.com")
      bob = create_user("cc_mr2", "cc_mr2@example.com")

      {:ok, conv} = Messaging.find_or_create_direct(alice.id, bob.id)
      {:ok, _} = Messaging.send_message(conv.id, alice.id, %{"content" => "Hello!"})

      conn =
        conn
        |> authenticate(bob)
        |> post("/api/v1/conversations/#{conv.id}/read")

      assert json_response(conn, 200)["message"] == "conversation.marked_read"
    end
  end

  # ---------------------------------------------------------------------------
  # Settings
  # ---------------------------------------------------------------------------

  describe "PATCH /api/v1/conversations/:id/settings" do
    test "mutes a conversation", %{conn: conn} do
      alice = create_user("cc_st", "cc_st@example.com")
      bob = create_user("cc_st2", "cc_st2@example.com")

      {:ok, conv} = Messaging.find_or_create_direct(alice.id, bob.id)

      conn =
        conn
        |> authenticate(alice)
        |> patch("/api/v1/conversations/#{conv.id}/settings", %{"notifications_enabled" => false})

      response = json_response(conn, 200)
      assert response["notifications_enabled"] == false
    end

    test "unmutes a conversation", %{conn: conn} do
      alice = create_user("cc_st3", "cc_st3@example.com")
      bob = create_user("cc_st4", "cc_st4@example.com")

      {:ok, conv} = Messaging.find_or_create_direct(alice.id, bob.id)
      {:ok, _} = Messaging.mute_conversation(conv.id, alice.id)

      conn =
        conn
        |> authenticate(alice)
        |> patch("/api/v1/conversations/#{conv.id}/settings", %{"notifications_enabled" => true})

      response = json_response(conn, 200)
      assert response["notifications_enabled"] == true
    end
  end

  # ---------------------------------------------------------------------------
  # DM Preferences
  # ---------------------------------------------------------------------------

  describe "GET /api/v1/dm_preferences" do
    test "returns default preferences", %{conn: conn} do
      alice = create_user("cc_dp", "cc_dp@example.com")

      conn =
        conn
        |> authenticate(alice)
        |> get("/api/v1/dm_preferences")

      response = json_response(conn, 200)
      assert response["allow_dms_from"] == "everyone"
      assert response["allow_group_dms"] == false
    end
  end

  describe "PATCH /api/v1/dm_preferences" do
    test "updates DM preferences", %{conn: conn} do
      alice = create_user("cc_dp2", "cc_dp2@example.com")

      conn =
        conn
        |> authenticate(alice)
        |> patch("/api/v1/dm_preferences", %{
          "allow_dms_from" => "followers",
          "allow_group_dms" => true
        })

      response = json_response(conn, 200)
      assert response["allow_dms_from"] == "followers"
      assert response["allow_group_dms"] == true
    end
  end
end
