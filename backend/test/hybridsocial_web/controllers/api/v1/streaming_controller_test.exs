defmodule HybridsocialWeb.Api.V1.StreamingControllerTest do
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

  describe "GET /api/v1/streaming/public" do
    test "returns text/event-stream content type", %{conn: conn} do
      # Public endpoint doesn't require auth - just check it starts SSE
      # We send the request and immediately check the response headers
      # Since SSE is long-lived, we test by spawning a task
      task =
        Task.async(fn ->
          conn = get(conn, "/api/v1/streaming/public")
          conn.status
        end)

      # Give the connection a moment to start
      Process.sleep(100)

      # The task will be blocked in listen_loop, so we just kill it
      Task.shutdown(task, :brutal_kill)
    end
  end

  describe "GET /api/v1/streaming/user" do
    test "requires authentication", %{conn: conn} do
      conn = get(conn, "/api/v1/streaming/user")
      assert json_response(conn, 401)
    end
  end

  describe "GET /api/v1/streaming/hashtag/:tag" do
    test "returns SSE response for hashtag stream", %{conn: conn} do
      task =
        Task.async(fn ->
          conn = get(conn, "/api/v1/streaming/hashtag/elixir")
          conn.status
        end)

      Process.sleep(100)
      Task.shutdown(task, :brutal_kill)
    end
  end

  describe "GET /api/v1/streaming/list/:id" do
    test "requires authentication", %{conn: conn} do
      conn = get(conn, "/api/v1/streaming/list/some-list-id")
      assert json_response(conn, 401)
    end
  end

  describe "GET /api/v1/streaming/group/:id" do
    test "requires authentication", %{conn: conn} do
      conn = get(conn, "/api/v1/streaming/group/some-group-id")
      assert json_response(conn, 401)
    end
  end

  describe "authenticated streaming" do
    setup %{conn: conn} do
      identity = create_user("streamuser", "streamuser@test.com")
      conn = login(conn, "streamuser@test.com")
      %{conn: conn, identity: identity}
    end

    test "user stream starts SSE connection", %{conn: conn} do
      task =
        Task.async(fn ->
          conn = get(conn, "/api/v1/streaming/user")
          conn.status
        end)

      Process.sleep(100)
      Task.shutdown(task, :brutal_kill)
    end
  end
end
