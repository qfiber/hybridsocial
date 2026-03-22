defmodule HybridsocialWeb.Federation.InboxControllerTest do
  use HybridsocialWeb.ConnCase, async: true

  alias Hybridsocial.Repo
  alias Hybridsocial.Accounts.Identity
  alias Hybridsocial.Social.Posts

  defp create_local_identity(handle) do
    %Identity{}
    |> Identity.create_changeset(%{
      "type" => "user",
      "handle" => handle,
      "display_name" => "Test User #{handle}"
    })
    |> Repo.insert!()
  end

  defp create_remote_identity(ap_id, handle) do
    id = Ecto.UUID.generate()

    %Identity{}
    |> Ecto.Changeset.cast(
      %{
        id: id,
        type: "user",
        handle: handle,
        ap_actor_url: ap_id,
        inbox_url: "#{ap_id}/inbox",
        outbox_url: "#{ap_id}/outbox",
        followers_url: "#{ap_id}/followers"
      },
      [:id, :type, :handle, :ap_actor_url, :inbox_url, :outbox_url, :followers_url]
    )
    |> Ecto.Changeset.validate_required([:type, :handle])
    |> Ecto.Changeset.unique_constraint(:handle)
    |> Repo.insert!()
  end

  defp base_url, do: HybridsocialWeb.Endpoint.url()

  describe "POST /actors/:id/inbox" do
    test "returns 202 for a valid Follow activity", %{conn: conn} do
      local = create_local_identity("inbox_ctrl_target")

      activity = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "https://remote.example/activities/ctrl-follow-1",
        "type" => "Follow",
        "actor" => "https://remote.example/users/ctrl_alice",
        "object" => "#{base_url()}/actors/#{local.id}"
      }

      conn =
        conn
        |> put_req_header("content-type", "application/activity+json")
        |> post("/actors/#{local.id}/inbox", activity)

      assert json_response(conn, 202)["status"] == "accepted"
    end

    test "returns 422 for invalid activity", %{conn: conn} do
      local = create_local_identity("inbox_ctrl_invalid")

      activity = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "https://remote.example/activities/invalid-1",
        "type" => "Follow",
        "actor" => "https://remote.example/users/invalid_actor"
        # Missing "object" field
      }

      conn =
        conn
        |> put_req_header("content-type", "application/activity+json")
        |> post("/actors/#{local.id}/inbox", activity)

      assert json_response(conn, 422)["error"] == "Unprocessable activity"
    end

    test "returns 422 for unsupported activity type", %{conn: conn} do
      local = create_local_identity("inbox_ctrl_unsupported")

      activity = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "https://remote.example/activities/unsupported-1",
        "type" => "TentativeAccept",
        "actor" => "https://remote.example/users/someone",
        "object" => "#{base_url()}/actors/#{local.id}"
      }

      conn =
        conn
        |> put_req_header("content-type", "application/activity+json")
        |> post("/actors/#{local.id}/inbox", activity)

      assert json_response(conn, 422)
    end
  end

  describe "POST /inbox (shared inbox)" do
    test "returns 202 for a valid Create activity", %{conn: conn} do
      remote_ap_id = "https://remote.example/users/shared_alice"

      activity = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "https://remote.example/activities/shared-create-1",
        "type" => "Create",
        "actor" => remote_ap_id,
        "object" => %{
          "id" => "https://remote.example/objects/shared-note-1",
          "type" => "Note",
          "content" => "<p>Hello from shared inbox!</p>",
          "attributedTo" => remote_ap_id,
          "published" => "2026-03-22T14:00:00Z",
          "to" => ["https://www.w3.org/ns/activitystreams#Public"]
        }
      }

      conn =
        conn
        |> put_req_header("content-type", "application/activity+json")
        |> post("/inbox", activity)

      assert json_response(conn, 202)["status"] == "accepted"
    end

    test "returns 202 for duplicate activities (idempotent)", %{conn: conn} do
      remote_ap_id = "https://remote.example/users/dedup_alice"

      activity = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "https://remote.example/activities/dedup-test-1",
        "type" => "Create",
        "actor" => remote_ap_id,
        "object" => %{
          "id" => "https://remote.example/objects/dedup-note-1",
          "type" => "Note",
          "content" => "Dedup test",
          "attributedTo" => remote_ap_id,
          "published" => "2026-03-22T14:00:00Z",
          "to" => ["https://www.w3.org/ns/activitystreams#Public"]
        }
      }

      # First request
      conn1 =
        conn
        |> put_req_header("content-type", "application/activity+json")
        |> post("/inbox", activity)

      assert json_response(conn1, 202)["status"] == "accepted"

      # Second request (same activity ID - should be deduped)
      conn2 =
        build_conn()
        |> put_req_header("content-type", "application/activity+json")
        |> post("/inbox", activity)

      assert json_response(conn2, 202)["status"] == "accepted"
    end

    test "returns 403 for suspended domains", %{conn: conn} do
      # Set up a suspended domain policy
      {:ok, _} =
        Hybridsocial.Federation.set_instance_policy("suspended.example", "suspend", "spam", nil)

      activity = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "https://suspended.example/activities/blocked-1",
        "type" => "Create",
        "actor" => "https://suspended.example/users/spammer",
        "object" => %{
          "id" => "https://suspended.example/objects/spam-1",
          "type" => "Note",
          "content" => "Spam content",
          "to" => ["https://www.w3.org/ns/activitystreams#Public"]
        }
      }

      conn =
        conn
        |> put_req_header("content-type", "application/activity+json")
        |> post("/inbox", activity)

      assert json_response(conn, 403)["error"] == "Domain suspended"
    end

    test "returns 202 for a Like activity", %{conn: conn} do
      local = create_local_identity("shared_like_target")
      {:ok, post} = Posts.create_post(local.id, %{"content" => "Likeable", "post_type" => "text"})
      remote = create_remote_identity("https://remote.example/users/shared_liker", "shared_liker")

      activity = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "https://remote.example/activities/shared-like-1",
        "type" => "Like",
        "actor" => remote.ap_actor_url,
        "object" => "#{base_url()}/objects/#{post.id}"
      }

      conn =
        conn
        |> put_req_header("content-type", "application/activity+json")
        |> post("/inbox", activity)

      assert json_response(conn, 202)["status"] == "accepted"
    end
  end
end
