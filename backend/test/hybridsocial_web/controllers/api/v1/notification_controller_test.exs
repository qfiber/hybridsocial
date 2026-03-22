defmodule HybridsocialWeb.Api.V1.NotificationControllerTest do
  use HybridsocialWeb.ConnCase, async: false

  alias Hybridsocial.Auth.Token
  alias Hybridsocial.Notifications

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
  # GET /api/v1/notifications
  # ---------------------------------------------------------------------------

  describe "GET /api/v1/notifications" do
    test "requires authentication", %{conn: conn} do
      conn = get(conn, "/api/v1/notifications")
      assert json_response(conn, 401)
    end

    test "returns empty list when no notifications exist", %{conn: conn} do
      alice = create_user("nc_alice1", "nc_alice1@example.com")

      conn =
        conn
        |> authenticate(alice)
        |> get("/api/v1/notifications")

      assert json_response(conn, 200) == []
    end

    test "returns notifications for the current user", %{conn: conn} do
      alice = create_user("nc_alice2", "nc_alice2@example.com")
      bob = create_user("nc_bob2", "nc_bob2@example.com")

      {:ok, _} =
        Notifications.create_notification(%{
          recipient_id: alice.id,
          actor_id: bob.id,
          type: "follow"
        })

      conn =
        conn
        |> authenticate(alice)
        |> get("/api/v1/notifications")

      response = json_response(conn, 200)
      assert length(response) == 1
      notification = hd(response)
      assert notification["type"] == "follow"
      assert notification["read"] == false
      assert notification["account"]["id"] == bob.id
      assert notification["account"]["handle"] == "nc_bob2"
    end

    test "does not return other users' notifications", %{conn: conn} do
      alice = create_user("nc_alice3", "nc_alice3@example.com")
      bob = create_user("nc_bob3", "nc_bob3@example.com")
      carol = create_user("nc_carol3", "nc_carol3@example.com")

      {:ok, _} =
        Notifications.create_notification(%{
          recipient_id: alice.id,
          actor_id: bob.id,
          type: "follow"
        })

      conn =
        conn
        |> authenticate(carol)
        |> get("/api/v1/notifications")

      assert json_response(conn, 200) == []
    end
  end

  # ---------------------------------------------------------------------------
  # GET /api/v1/notifications/:id
  # ---------------------------------------------------------------------------

  describe "GET /api/v1/notifications/:id" do
    test "returns a notification", %{conn: conn} do
      alice = create_user("nc_alice4", "nc_alice4@example.com")
      bob = create_user("nc_bob4", "nc_bob4@example.com")

      {:ok, notif} =
        Notifications.create_notification(%{
          recipient_id: alice.id,
          actor_id: bob.id,
          type: "follow"
        })

      conn =
        conn
        |> authenticate(alice)
        |> get("/api/v1/notifications/#{notif.id}")

      response = json_response(conn, 200)
      assert response["id"] == notif.id
      assert response["type"] == "follow"
    end

    test "returns 404 for non-existent notification", %{conn: conn} do
      alice = create_user("nc_alice5", "nc_alice5@example.com")

      conn =
        conn
        |> authenticate(alice)
        |> get("/api/v1/notifications/#{Ecto.UUID.generate()}")

      assert json_response(conn, 404)
    end

    test "returns 404 for other user's notification", %{conn: conn} do
      alice = create_user("nc_alice6", "nc_alice6@example.com")
      bob = create_user("nc_bob6", "nc_bob6@example.com")
      carol = create_user("nc_carol6", "nc_carol6@example.com")

      {:ok, notif} =
        Notifications.create_notification(%{
          recipient_id: alice.id,
          actor_id: bob.id,
          type: "follow"
        })

      conn =
        conn
        |> authenticate(carol)
        |> get("/api/v1/notifications/#{notif.id}")

      assert json_response(conn, 404)
    end
  end

  # ---------------------------------------------------------------------------
  # POST /api/v1/notifications/clear
  # ---------------------------------------------------------------------------

  describe "POST /api/v1/notifications/clear" do
    test "marks all notifications as read", %{conn: conn} do
      alice = create_user("nc_alice7", "nc_alice7@example.com")
      bob = create_user("nc_bob7", "nc_bob7@example.com")

      for _ <- 1..3 do
        Notifications.create_notification(%{
          recipient_id: alice.id,
          actor_id: bob.id,
          type: "follow"
        })
      end

      assert Notifications.unread_count(alice.id) == 3

      conn =
        conn
        |> authenticate(alice)
        |> post("/api/v1/notifications/clear")

      assert json_response(conn, 200)["message"] == "notifications.cleared"
      assert Notifications.unread_count(alice.id) == 0
    end
  end

  # ---------------------------------------------------------------------------
  # POST /api/v1/notifications/:id/read
  # ---------------------------------------------------------------------------

  describe "POST /api/v1/notifications/:id/read" do
    test "marks a notification as read", %{conn: conn} do
      alice = create_user("nc_alice8", "nc_alice8@example.com")
      bob = create_user("nc_bob8", "nc_bob8@example.com")

      {:ok, notif} =
        Notifications.create_notification(%{
          recipient_id: alice.id,
          actor_id: bob.id,
          type: "follow"
        })

      conn =
        conn
        |> authenticate(alice)
        |> post("/api/v1/notifications/#{notif.id}/read")

      response = json_response(conn, 200)
      assert response["read"] == true
    end

    test "returns 404 for non-existent notification", %{conn: conn} do
      alice = create_user("nc_alice9", "nc_alice9@example.com")

      conn =
        conn
        |> authenticate(alice)
        |> post("/api/v1/notifications/#{Ecto.UUID.generate()}/read")

      assert json_response(conn, 404)
    end
  end

  # ---------------------------------------------------------------------------
  # DELETE /api/v1/notifications/:id
  # ---------------------------------------------------------------------------

  describe "DELETE /api/v1/notifications/:id" do
    test "dismisses a notification", %{conn: conn} do
      alice = create_user("nc_alice10", "nc_alice10@example.com")
      bob = create_user("nc_bob10", "nc_bob10@example.com")

      {:ok, notif} =
        Notifications.create_notification(%{
          recipient_id: alice.id,
          actor_id: bob.id,
          type: "follow"
        })

      conn =
        conn
        |> authenticate(alice)
        |> delete("/api/v1/notifications/#{notif.id}")

      assert json_response(conn, 200)["message"] == "notification.dismissed"
      assert is_nil(Notifications.get_notification(notif.id, alice.id))
    end

    test "returns 404 for non-existent notification", %{conn: conn} do
      alice = create_user("nc_alice11", "nc_alice11@example.com")

      conn =
        conn
        |> authenticate(alice)
        |> delete("/api/v1/notifications/#{Ecto.UUID.generate()}")

      assert json_response(conn, 404)
    end
  end

  # ---------------------------------------------------------------------------
  # GET /api/v1/notification_preferences
  # ---------------------------------------------------------------------------

  describe "GET /api/v1/notification_preferences" do
    test "returns empty map when no preferences set", %{conn: conn} do
      alice = create_user("nc_alice12", "nc_alice12@example.com")

      conn =
        conn
        |> authenticate(alice)
        |> get("/api/v1/notification_preferences")

      assert json_response(conn, 200) == %{}
    end

    test "returns preferences map", %{conn: conn} do
      alice = create_user("nc_alice13", "nc_alice13@example.com")

      {:ok, _} = Notifications.update_preference(alice.id, "follow", %{"email" => true, "push" => false})

      conn =
        conn
        |> authenticate(alice)
        |> get("/api/v1/notification_preferences")

      response = json_response(conn, 200)
      assert response["follow"]["email"] == true
      assert response["follow"]["push"] == false
      assert response["follow"]["in_app"] == true
    end
  end

  # ---------------------------------------------------------------------------
  # PATCH /api/v1/notification_preferences
  # ---------------------------------------------------------------------------

  describe "PATCH /api/v1/notification_preferences" do
    test "updates a preference", %{conn: conn} do
      alice = create_user("nc_alice14", "nc_alice14@example.com")

      conn =
        conn
        |> authenticate(alice)
        |> patch("/api/v1/notification_preferences", %{
          "type" => "follow",
          "email" => true,
          "push" => false,
          "in_app" => true
        })

      response = json_response(conn, 200)
      assert response["type"] == "follow"
      assert response["email"] == true
      assert response["push"] == false
      assert response["in_app"] == true
    end

    test "returns error when type is missing", %{conn: conn} do
      alice = create_user("nc_alice15", "nc_alice15@example.com")

      conn =
        conn
        |> authenticate(alice)
        |> patch("/api/v1/notification_preferences", %{"email" => true})

      assert json_response(conn, 422)["error"] == "notification_preferences.type_required"
    end
  end
end
