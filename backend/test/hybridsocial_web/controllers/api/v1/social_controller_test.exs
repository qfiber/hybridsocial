defmodule HybridsocialWeb.Api.V1.SocialControllerTest do
  use HybridsocialWeb.ConnCase, async: true

  alias Hybridsocial.Accounts
  alias Hybridsocial.Social

  defp create_and_login(conn, handle, email) do
    {:ok, identity} =
      Accounts.register_user(%{
        "handle" => handle,
        "email" => email,
        "password" => "password123",
        "password_confirmation" => "password123"
      })

    {:ok, tokens} = Hybridsocial.Auth.login(email, "password123")
    {identity, put_req_header(conn, "authorization", "Bearer #{tokens.access_token}")}
  end

  setup %{conn: conn} do
    {alice, alice_conn} = create_and_login(conn, "alice", "alice@example.com")
    {bob, bob_conn} = create_and_login(conn, "bob", "bob@example.com")
    %{alice: alice, alice_conn: alice_conn, bob: bob, bob_conn: bob_conn, conn: conn}
  end

  # --- Follow ---

  describe "POST /api/v1/accounts/:id/follow" do
    test "follows a user", %{alice_conn: conn, bob: bob} do
      resp = conn |> post("/api/v1/accounts/#{bob.id}/follow") |> json_response(200)
      assert resp["following"] == true
      assert resp["id"] == bob.id
    end

    test "returns pending for locked account", %{alice_conn: conn} do
      {locked, _} = create_and_login(conn, "locked_user", "locked@example.com")
      {:ok, _} = Accounts.update_identity(locked, %{"is_locked" => true})

      resp = conn |> post("/api/v1/accounts/#{locked.id}/follow") |> json_response(200)
      assert resp["requested"] == true
      assert resp["following"] == false
    end

    test "returns 401 without auth", %{conn: conn, bob: bob} do
      conn |> post("/api/v1/accounts/#{bob.id}/follow") |> json_response(401)
    end
  end

  # --- Unfollow ---

  describe "POST /api/v1/accounts/:id/unfollow" do
    test "unfollows a user", %{alice_conn: conn, alice: alice, bob: bob} do
      {:ok, _} = Social.follow(alice.id, bob.id)

      resp = conn |> post("/api/v1/accounts/#{bob.id}/unfollow") |> json_response(200)
      assert resp["following"] == false
    end
  end

  # --- Block ---

  describe "POST /api/v1/accounts/:id/block" do
    test "blocks a user", %{alice_conn: conn, bob: bob} do
      resp = conn |> post("/api/v1/accounts/#{bob.id}/block") |> json_response(200)
      assert resp["blocking"] == true
    end

    test "removes follow when blocking", %{alice_conn: conn, alice: alice, bob: bob} do
      {:ok, _} = Social.follow(alice.id, bob.id)
      assert Social.following?(alice.id, bob.id)

      conn |> post("/api/v1/accounts/#{bob.id}/block") |> json_response(200)
      refute Social.following?(alice.id, bob.id)
    end
  end

  # --- Unblock ---

  describe "POST /api/v1/accounts/:id/unblock" do
    test "unblocks a user", %{alice_conn: conn, alice: alice, bob: bob} do
      {:ok, _} = Social.block(alice.id, bob.id)

      resp = conn |> post("/api/v1/accounts/#{bob.id}/unblock") |> json_response(200)
      assert resp["blocking"] == false
    end
  end

  # --- Mute ---

  describe "POST /api/v1/accounts/:id/mute" do
    test "mutes a user", %{alice_conn: conn, bob: bob} do
      resp = conn |> post("/api/v1/accounts/#{bob.id}/mute") |> json_response(200)
      assert resp["muting"] == true
    end
  end

  # --- Unmute ---

  describe "POST /api/v1/accounts/:id/unmute" do
    test "unmutes a user", %{alice_conn: conn, alice: alice, bob: bob} do
      {:ok, _} = Social.mute(alice.id, bob.id)

      resp = conn |> post("/api/v1/accounts/#{bob.id}/unmute") |> json_response(200)
      assert resp["muting"] == false
    end
  end

  # --- Followers / Following ---

  describe "GET /api/v1/accounts/:id/followers" do
    test "returns followers list", %{conn: conn, alice: alice, bob: bob} do
      {:ok, _} = Social.follow(bob.id, alice.id)

      resp = conn |> get("/api/v1/accounts/#{alice.id}/followers") |> json_response(200)
      assert length(resp) == 1
      assert hd(resp)["id"] == bob.id
    end

    test "works without authentication", %{conn: conn, alice: alice, bob: bob} do
      {:ok, _} = Social.follow(bob.id, alice.id)

      resp = conn |> get("/api/v1/accounts/#{alice.id}/followers") |> json_response(200)
      assert length(resp) == 1
    end
  end

  describe "GET /api/v1/accounts/:id/following" do
    test "returns following list", %{conn: conn, alice: alice, bob: bob} do
      {:ok, _} = Social.follow(alice.id, bob.id)

      resp = conn |> get("/api/v1/accounts/#{alice.id}/following") |> json_response(200)
      assert length(resp) == 1
      assert hd(resp)["id"] == bob.id
    end
  end

  # --- Relationships ---

  describe "GET /api/v1/accounts/relationships" do
    test "returns relationship status for multiple targets", %{alice_conn: conn, alice: alice, bob: bob} do
      {:ok, _} = Social.follow(alice.id, bob.id)

      resp = conn |> get("/api/v1/accounts/relationships", %{"ids" => [bob.id]}) |> json_response(200)
      assert length(resp) == 1

      bob_rel = hd(resp)
      assert bob_rel["id"] == bob.id
      assert bob_rel["following"] == true
    end

    test "returns 401 without auth", %{conn: conn, bob: bob} do
      conn |> get("/api/v1/accounts/relationships", %{"ids" => [bob.id]}) |> json_response(401)
    end
  end
end
