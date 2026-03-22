defmodule HybridsocialWeb.Api.V1.PollControllerTest do
  use HybridsocialWeb.ConnCase, async: true

  alias Hybridsocial.Social.{Posts, Polls}

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
    identity = create_user("polltestuser", "polltestuser@test.com")
    conn = login(conn, "polltestuser@test.com")
    %{conn: conn, identity: identity}
  end

  describe "GET /api/v1/polls/:id" do
    setup :setup_user

    test "shows a poll", %{conn: conn, identity: identity} do
      {:ok, post} =
        Posts.create_post(identity.id, %{
          "content" => "Poll question?",
          "post_type" => "poll",
          "options" => ["Yes", "No"],
          "multiple_choice" => false
        })

      poll = Polls.get_poll(post.id)

      conn = get(conn, "/api/v1/polls/#{poll.id}")
      response = json_response(conn, 200)
      assert response["id"] == poll.id
      assert length(response["options"]) == 2
      assert response["multiple_choice"] == false
    end

    test "returns 404 for non-existent poll", %{conn: conn} do
      fake_id = Ecto.UUID.generate()
      conn = get(conn, "/api/v1/polls/#{fake_id}")
      assert json_response(conn, 404)["error"] == "poll.not_found"
    end
  end

  describe "POST /api/v1/polls/:id/votes" do
    setup :setup_user

    test "casts a vote", %{conn: conn, identity: identity} do
      {:ok, post} =
        Posts.create_post(identity.id, %{
          "content" => "Vote question?",
          "post_type" => "poll",
          "options" => ["Option A", "Option B"],
          "multiple_choice" => false
        })

      poll = Polls.get_poll(post.id)
      option = hd(poll.options)

      conn = post(conn, "/api/v1/polls/#{poll.id}/votes", %{"choices" => [option.id]})
      response = json_response(conn, 200)
      assert response["voters_count"] == 1
    end

    test "returns error for expired poll", %{conn: conn, identity: identity} do
      {:ok, post} = Posts.create_post(identity.id, %{"content" => "Expired poll"})

      past = DateTime.add(DateTime.utc_now(), -3600, :second)

      {:ok, poll} =
        Polls.create_poll(post.id, %{
          "options" => ["Yes", "No"],
          "expires_at" => past
        })

      option = hd(poll.options)

      conn = post(conn, "/api/v1/polls/#{poll.id}/votes", %{"choices" => [option.id]})
      assert json_response(conn, 422)["error"] == "poll.expired"
    end

    test "returns error for invalid options", %{conn: conn, identity: identity} do
      {:ok, post} =
        Posts.create_post(identity.id, %{
          "content" => "Poll?",
          "post_type" => "poll",
          "options" => ["A", "B"]
        })

      poll = Polls.get_poll(post.id)
      fake_option = Ecto.UUID.generate()

      conn = post(conn, "/api/v1/polls/#{poll.id}/votes", %{"choices" => [fake_option]})
      assert json_response(conn, 422)["error"] == "poll.invalid_options"
    end
  end
end
