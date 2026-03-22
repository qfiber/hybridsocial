defmodule HybridsocialWeb.Api.V1.CustomEmojiControllerTest do
  use HybridsocialWeb.ConnCase, async: true

  alias Hybridsocial.Content.Emojis

  describe "GET /api/v1/custom_emojis" do
    test "returns list of enabled emojis", %{conn: conn} do
      {:ok, _} =
        Emojis.create_emoji(%{
          "shortcode" => "test_emoji",
          "image_url" => "https://example.com/test.png",
          "category" => "test"
        })

      {:ok, _} =
        Emojis.create_emoji(%{
          "shortcode" => "disabled_emoji",
          "image_url" => "https://example.com/disabled.png",
          "enabled" => false
        })

      conn = get(conn, "/api/v1/custom_emojis")
      response = json_response(conn, 200)

      assert is_list(response)
      assert length(response) == 1
      assert hd(response)["shortcode"] == "test_emoji"
      assert hd(response)["image_url"] == "https://example.com/test.png"
    end

    test "filters by category", %{conn: conn} do
      {:ok, _} =
        Emojis.create_emoji(%{
          "shortcode" => "cat_emoji",
          "image_url" => "https://example.com/cat.png",
          "category" => "animals"
        })

      {:ok, _} =
        Emojis.create_emoji(%{
          "shortcode" => "face_emoji",
          "image_url" => "https://example.com/face.png",
          "category" => "faces"
        })

      conn = get(conn, "/api/v1/custom_emojis?category=animals")
      response = json_response(conn, 200)

      assert length(response) == 1
      assert hd(response)["shortcode"] == "cat_emoji"
    end

    test "returns empty list when no emojis exist", %{conn: conn} do
      conn = get(conn, "/api/v1/custom_emojis")
      response = json_response(conn, 200)
      assert response == []
    end
  end
end
