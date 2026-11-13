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
      local = create_local_identity("inbox_unsupported")

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

    # Regression: the controller used to pass the merged `params` to
    # Inbox.process, which let the route's `:id` (a local UUID) shadow the
    # activity's own "id" field. Containment then compared the local
    # UUID's host against the actor's host and rejected every Follow as
    # an origin mismatch. The fix is to read conn.body_params instead;
    # this test pins that behavior so it can't silently regress.
    test "preserves the activity's own id when route :id is a local UUID", %{conn: conn} do
      local = create_local_identity("inbox_id_shadow")
      remote_actor = "https://remote.example/users/eve_shadow"
      activity_id = "https://remote.example/activities/preserved-create-1"
      object_id = "https://remote.example/objects/preserved-note-1"

      activity = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => activity_id,
        "type" => "Create",
        "actor" => remote_actor,
        "object" => %{
          "id" => object_id,
          "type" => "Note",
          "content" => "<p>route id must not shadow this</p>",
          "attributedTo" => remote_actor,
          "published" => "2026-04-13T12:00:00Z",
          "to" => ["https://www.w3.org/ns/activitystreams#Public"]
        }
      }

      conn =
        conn
        |> put_req_header("content-type", "application/activity+json")
        |> post("/actors/#{local.id}/inbox", activity)

      assert json_response(conn, 202)["status"] == "accepted"

      # If the body's id was preserved, the post landed in the DB with
      # the object id from the body (not the route's UUID).
      assert post = Repo.get_by(Hybridsocial.Social.Post, ap_id: object_id)
      assert post.ap_id == object_id
      refute post.ap_id == local.id

      # And dedup must remember the body's activity id, not the route id.
      activity_hash = :crypto.hash(:sha256, activity_id) |> Base.encode16(case: :lower)
      assert Hybridsocial.Federation.deduplicate?(activity_hash)
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
  end

  describe "Digest header enforcement (production-like)" do
    setup do
      # DigestPlug's "missing-Digest is fatal" behavior is paired with the
      # federation_signature_check env (default true in prod, false in test
      # so existing fixtures don't need handcrafted signatures). Flip it on
      # for these tests, then restore.
      prev = Application.get_env(:hybridsocial, :federation_signature_check, true)
      Application.put_env(:hybridsocial, :federation_signature_check, true)
      on_exit(fn -> Application.put_env(:hybridsocial, :federation_signature_check, prev) end)
      :ok
    end

    test "rejects POST /inbox without a Digest header", %{conn: conn} do
      activity = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "https://remote.example/activities/no-digest-1",
        "type" => "Follow",
        "actor" => "https://remote.example/users/no_digest",
        "object" => "#{base_url()}/actor"
      }

      conn =
        conn
        |> put_req_header("content-type", "application/activity+json")
        # Deliberately no Digest header.
        |> post("/inbox", activity)

      assert json_response(conn, 401)["error"] == "Digest header required"
    end

    test "logs who sent a Digest-less POST and how it was signed", %{conn: conn} do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          conn
          |> put_req_header("content-type", "application/activity+json")
          |> put_req_header(
            "signature-input",
            ~s|sig1=("@method");keyid="https://rfc9421.example/users/a#main-key"|
          )
          |> put_req_header("content-digest", "sha-256=:abc=:")
          |> post("/inbox", %{"type" => "Follow"})
        end)

      assert log =~ "missing Digest header"
      assert log =~ "from=rfc9421.example"
      assert log =~ "content_digest=true"
      assert log =~ "signature_input=true"
      assert log =~ "signature=false"
    end
  end

  describe "Digest mismatch (always-on)" do
    test "rejects POST /inbox with a Digest that doesn't match the body", %{conn: conn} do
      activity = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "https://remote.example/activities/bad-digest-1",
        "type" => "Follow",
        "actor" => "https://remote.example/users/bad_digest",
        "object" => "#{base_url()}/actor"
      }

      conn =
        conn
        |> put_req_header("content-type", "application/activity+json")
        |> put_req_header("digest", "SHA-256=" <> Base.encode64(:crypto.hash(:sha256, "wrong")))
        |> post("/inbox", activity)

      assert json_response(conn, 401)["error"] == "Invalid digest"
    end
  end

  describe "actor / keyId origin cross-check" do
    setup do
      # The cross-check only fires when signature verification is enabled;
      # test env disables it by default. Flip it on for these tests, then
      # restore so we don't leak into other tests.
      prev = Application.get_env(:hybridsocial, :federation_signature_check, true)
      Application.put_env(:hybridsocial, :federation_signature_check, true)
      on_exit(fn -> Application.put_env(:hybridsocial, :federation_signature_check, prev) end)
      :ok
    end

    test "rejects an activity whose actor's origin doesn't match the keyId's origin",
         %{conn: conn} do
      local = create_local_identity("xorigin_target")

      # Build a signed POST where the keyId is from "remote.example" but
      # the activity claims "actor": "https://victim.example/users/foo".
      # The verifier won't reach origin check unless the signature parses,
      # so we send a syntactically valid Signature header — the origin
      # check fires once verify returns ok-or-error, and rejects this
      # cross-origin claim before any state mutation.
      activity = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "https://attacker.example/activities/spoof-1",
        "type" => "Follow",
        "actor" => "https://victim.example/users/foo",
        "object" => "#{base_url()}/actors/#{local.id}"
      }

      body = Jason.encode!(activity)
      digest = "SHA-256=" <> Base.encode64(:crypto.hash(:sha256, body))

      # The Signature itself is invalid (we don't have attacker's key)
      # so HTTPSignature.verify will return :signature_invalid before
      # the origin check runs. That's the right ordering — a bad
      # signature is rejected first. We assert the response is 401
      # regardless of which check tripped.
      conn =
        conn
        |> put_req_header("content-type", "application/activity+json")
        |> put_req_header("digest", digest)
        |> put_req_header(
          "date",
          Calendar.strftime(DateTime.utc_now(), "%a, %d %b %Y %H:%M:%S GMT")
        )
        |> put_req_header(
          "signature",
          ~s|keyId="https://attacker.example/users/x#main-key",algorithm="rsa-sha256",headers="(request-target) host date digest",signature="ZmFrZQ=="|
        )
        # Post the raw body we hashed for the digest, not the map (which
        # would be re-encoded and fail the digest check before signature
        # verification — the check we're actually asserting on).
        |> post("/actors/#{local.id}/inbox", body)

      assert json_response(conn, 401)["error"] == "Invalid HTTP signature"
    end
  end

  describe "Like activity (legacy compatibility)" do
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
