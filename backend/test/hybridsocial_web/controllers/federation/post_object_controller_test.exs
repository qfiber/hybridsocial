defmodule HybridsocialWeb.Federation.PostObjectControllerTest do
  use HybridsocialWeb.ConnCase, async: true

  alias Hybridsocial.Social.Posts

  setup do
    author = create_user("objauthor")

    {:ok, post} =
      Posts.create_post(author.id, %{"content" => "hello fediverse", "visibility" => "public"})

    %{post: post}
  end

  test "serves the Note to an ActivityPub client", %{conn: conn, post: post} do
    conn =
      conn |> put_req_header("accept", "application/activity+json") |> get("/posts/#{post.id}")

    assert %{"type" => "Note", "id" => id} = json_response(conn, 200)
    assert id == post.ap_id
  end

  test "honours the ld+json profile Accept", %{conn: conn, post: post} do
    accept = ~s(application/ld+json; profile="https://www.w3.org/ns/activitystreams")
    conn = conn |> put_req_header("accept", accept) |> get("/posts/#{post.id}")
    assert %{"type" => "Note"} = json_response(conn, 200)
  end

  # A person opening the object id gets the human page, not a 406.
  test "redirects a browser to the post page", %{conn: conn, post: post} do
    conn =
      conn
      |> put_req_header(
        "accept",
        "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
      )
      |> get("/posts/#{post.id}")

    assert redirected_to(conn) == "/post/#{post.id}"
  end
end
