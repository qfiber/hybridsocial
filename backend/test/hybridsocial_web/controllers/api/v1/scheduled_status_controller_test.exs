defmodule HybridsocialWeb.Api.V1.ScheduledStatusControllerTest do
  use HybridsocialWeb.ConnCase, async: true

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
    identity = create_user("scheduser", "scheduser@test.com")
    conn = login(conn, "scheduser@test.com")
    %{conn: conn, identity: identity}
  end

  defp future_time(seconds \\ 3600) do
    DateTime.utc_now()
    |> DateTime.add(seconds, :second)
    |> DateTime.truncate(:microsecond)
    |> DateTime.to_iso8601()
  end

  describe "POST /api/v1/statuses/schedule" do
    setup :setup_user

    test "schedules a post", %{conn: conn} do
      scheduled = future_time()

      conn =
        post(conn, "/api/v1/statuses/schedule", %{
          "content" => "Scheduled post",
          "scheduled_at" => scheduled
        })

      response = json_response(conn, 201)
      assert response["content"] == "Scheduled post"
      assert response["scheduled_at"] != nil
    end

    test "rejects post without scheduled_at", %{conn: conn} do
      conn =
        post(conn, "/api/v1/statuses/schedule", %{
          "content" => "No time"
        })

      assert json_response(conn, 422)
    end

    test "requires authentication", %{conn: _conn} do
      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/api/v1/statuses/schedule", %{
          "content" => "Unauthed",
          "scheduled_at" => future_time()
        })

      assert json_response(conn, 401)
    end
  end

  describe "GET /api/v1/scheduled_statuses" do
    setup :setup_user

    test "lists scheduled posts", %{conn: conn} do
      post(conn, "/api/v1/statuses/schedule", %{
        "content" => "Scheduled 1",
        "scheduled_at" => future_time(7200)
      })

      post(conn, "/api/v1/statuses/schedule", %{
        "content" => "Scheduled 2",
        "scheduled_at" => future_time(3600)
      })

      conn = get(conn, "/api/v1/scheduled_statuses")
      response = json_response(conn, 200)
      assert is_list(response)
      assert length(response) == 2
    end

    test "returns empty list when no scheduled posts", %{conn: conn} do
      conn = get(conn, "/api/v1/scheduled_statuses")
      response = json_response(conn, 200)
      assert response == []
    end
  end

  describe "PUT /api/v1/scheduled_statuses/:id" do
    setup :setup_user

    test "updates a scheduled post", %{conn: conn} do
      resp =
        post(conn, "/api/v1/statuses/schedule", %{
          "content" => "Original",
          "scheduled_at" => future_time()
        })

      %{"id" => id} = json_response(resp, 201)

      conn = put(conn, "/api/v1/scheduled_statuses/#{id}", %{"content" => "Updated"})
      response = json_response(conn, 200)
      assert response["content"] == "Updated"
    end

    test "returns not_found for nonexistent post", %{conn: conn} do
      conn = put(conn, "/api/v1/scheduled_statuses/#{Ecto.UUID.generate()}", %{"content" => "x"})
      assert json_response(conn, 404)["error"] == "scheduled_status.not_found"
    end
  end

  describe "DELETE /api/v1/scheduled_statuses/:id" do
    setup :setup_user

    test "cancels a scheduled post", %{conn: conn} do
      resp =
        post(conn, "/api/v1/statuses/schedule", %{
          "content" => "Cancel me",
          "scheduled_at" => future_time()
        })

      %{"id" => id} = json_response(resp, 201)

      conn = delete(conn, "/api/v1/scheduled_statuses/#{id}")
      assert json_response(conn, 200)["message"] == "scheduled_status.cancelled"
    end

    test "returns not_found for nonexistent post", %{conn: conn} do
      conn = delete(conn, "/api/v1/scheduled_statuses/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)["error"] == "scheduled_status.not_found"
    end
  end
end
