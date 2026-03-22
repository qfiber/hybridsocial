defmodule HybridsocialWeb.Api.V1.TrendControllerTest do
  use HybridsocialWeb.ConnCase, async: true

  alias Hybridsocial.Search.TrendingData
  alias Hybridsocial.Repo

  describe "GET /api/v1/trends/tags" do
    test "returns trending hashtags", %{conn: conn} do
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      %TrendingData{}
      |> TrendingData.changeset(%{
        type: "hashtag",
        target_id: "elixir",
        score: 10.5,
        computed_at: now,
        metadata: %{post_count: 5, unique_accounts: 3}
      })
      |> Repo.insert!()

      conn = get(conn, "/api/v1/trends/tags")
      response = json_response(conn, 200)

      assert is_list(response)
      assert length(response) >= 1
      assert hd(response)["name"] == "elixir"
      assert hd(response)["score"] == 10.5
    end

    test "returns empty list when no trending data", %{conn: conn} do
      conn = get(conn, "/api/v1/trends/tags")
      assert json_response(conn, 200) == []
    end
  end

  describe "GET /api/v1/trends/statuses" do
    test "returns empty list when no trending posts", %{conn: conn} do
      conn = get(conn, "/api/v1/trends/statuses")
      assert json_response(conn, 200) == []
    end

    test "returns trending posts with data", %{conn: conn} do
      user = create_user("trendpost", "trendpost@test.com")

      {:ok, post} =
        Hybridsocial.Social.Posts.create_post(user.id, %{
          "content" => "Trending!"
        })

      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      %TrendingData{}
      |> TrendingData.changeset(%{
        type: "post",
        target_id: post.id,
        score: 25.0,
        computed_at: now,
        metadata: %{engagement: 10, unique_accounts: 5}
      })
      |> Repo.insert!()

      conn = get(conn, "/api/v1/trends/statuses")
      response = json_response(conn, 200)

      assert length(response) >= 1
      assert hd(response)["id"] == post.id
      assert hd(response)["score"] == 25.0
    end
  end

  describe "GET /api/v1/trends/links" do
    test "returns empty list (placeholder)", %{conn: conn} do
      conn = get(conn, "/api/v1/trends/links")
      assert json_response(conn, 200) == []
    end
  end

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
end
