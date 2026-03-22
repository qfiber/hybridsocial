defmodule HybridsocialWeb.Api.V1.SearchControllerTest do
  use HybridsocialWeb.ConnCase, async: true

  alias Hybridsocial.Social.Posts

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

  describe "GET /api/v1/search" do
    test "searches accounts without auth", %{conn: conn} do
      _user = create_user("searchctrl", "searchctrl@test.com")

      conn = get(conn, "/api/v1/search", %{"q" => "searchctrl"})
      response = json_response(conn, 200)

      assert is_list(response["accounts"])
      assert length(response["accounts"]) >= 1
      assert hd(response["accounts"])["handle"] == "searchctrl"
    end

    test "searches posts", %{conn: conn} do
      user = create_user("postfinder", "postfinder@test.com")
      {:ok, _post} = Posts.create_post(user.id, %{"content" => "Unique xvbrkm content"})

      conn = get(conn, "/api/v1/search", %{"q" => "xvbrkm", "type" => "posts"})
      response = json_response(conn, 200)

      assert is_list(response["statuses"])
      assert length(response["statuses"]) >= 1
    end

    test "searches hashtags", %{conn: conn} do
      user = create_user("hashfinder", "hashfinder@test.com")
      {:ok, _post} = Posts.create_post(user.id, %{"content" => "Check out #findthis123"})

      conn = get(conn, "/api/v1/search", %{"q" => "findthis123", "type" => "hashtags"})
      response = json_response(conn, 200)

      assert is_list(response["hashtags"])
      assert length(response["hashtags"]) >= 1
    end

    test "returns all types when no type specified", %{conn: conn} do
      _user = create_user("allsearch", "allsearch@test.com")

      conn = get(conn, "/api/v1/search", %{"q" => "allsearch"})
      response = json_response(conn, 200)

      assert Map.has_key?(response, "accounts")
      assert Map.has_key?(response, "statuses")
      assert Map.has_key?(response, "hashtags")
      assert Map.has_key?(response, "groups")
    end

    test "returns empty results for blank query", %{conn: conn} do
      conn = get(conn, "/api/v1/search", %{"q" => ""})
      response = json_response(conn, 200)

      assert response["accounts"] == []
      assert response["statuses"] == []
    end

    test "works with authenticated user", %{conn: conn} do
      user = create_user("authsearch", "authsearch@test.com")
      conn = login(conn, "authsearch@test.com")

      {:ok, _post} =
        Posts.create_post(user.id, %{
          "content" => "Private nqwtps content",
          "visibility" => "followers"
        })

      conn = get(conn, "/api/v1/search", %{"q" => "nqwtps", "type" => "posts"})
      response = json_response(conn, 200)

      assert length(response["statuses"]) >= 1
    end
  end
end
