defmodule HybridsocialWeb.Api.V1.AdminControllerTest do
  use HybridsocialWeb.ConnCase

  alias Hybridsocial.Moderation
  alias Hybridsocial.Auth.RBAC

  # User/admin/moderator factories and the auth_conn/admin_conn helpers
  # come from Hybridsocial.AccountsFixtures (auto-imported by ConnCase).
  # admin_conn/2 also opens the sudo window every admin route requires.

  describe "admin reports" do
    setup %{conn: conn} do
      admin = create_user("admin1", "admin1@test.com") |> make_admin()
      user = create_user("user1", "user1@test.com")
      reported = create_user("reported1", "reported1@test.com")

      {:ok, report} =
        Moderation.create_report(user.id, %{
          "reported_id" => reported.id,
          "category" => "spam",
          "description" => "Test report"
        })

      %{
        conn: admin_conn(conn, admin),
        admin: admin,
        user: user,
        reported: reported,
        report: report
      }
    end

    test "GET /api/v1/admin/reports lists reports", %{conn: conn} do
      conn = get(conn, "/api/v1/admin/reports")
      assert %{"data" => data} = json_response(conn, 200)
      assert length(data) == 1
    end

    test "GET /api/v1/admin/reports/:id shows a report", %{conn: conn, report: report} do
      conn = get(conn, "/api/v1/admin/reports/#{report.id}")
      assert %{"data" => data} = json_response(conn, 200)
      assert data["id"] == report.id
    end

    test "POST /api/v1/admin/reports/:id/resolve resolves report", %{conn: conn, report: report} do
      conn =
        post(conn, "/api/v1/admin/reports/#{report.id}/resolve", %{"action_taken" => "warned"})

      assert %{"data" => data} = json_response(conn, 200)
      assert data["status"] == "resolved"
      assert data["action_taken"] == "warned"
    end

    test "POST /api/v1/admin/reports/:id/assign assigns report", %{
      conn: conn,
      report: report,
      admin: admin
    } do
      conn = post(conn, "/api/v1/admin/reports/#{report.id}/assign", %{})
      assert %{"data" => data} = json_response(conn, 200)
      assert data["status"] == "investigating"
      assert data["assigned_to"] == admin.id
      assert data["assigned_moderator"]["id"] == admin.id
    end

    test "status=open returns pending and investigating, not closed", %{
      conn: conn,
      admin: admin,
      user: user,
      reported: reported,
      report: report
    } do
      {:ok, investigating} =
        Moderation.create_report(user.id, %{"reported_id" => reported.id, "category" => "spam"})

      {:ok, _} = Moderation.assign_report(investigating.id, admin.id)

      {:ok, closed} =
        Moderation.create_report(user.id, %{"reported_id" => reported.id, "category" => "other"})

      {:ok, _} = Moderation.dismiss_report(closed.id, admin.id)

      ids =
        get(conn, "/api/v1/admin/reports?status=open")
        |> json_response(200)
        |> Map.fetch!("data")
        |> Enum.map(& &1["id"])
        |> MapSet.new()

      assert ids == MapSet.new([report.id, investigating.id])

      assert [%{"id" => id}] =
               get(conn, "/api/v1/admin/reports?status=dismissed")
               |> json_response(200)
               |> Map.fetch!("data")

      assert id == closed.id
    end

    test "detail embeds the reported post, the action trail and related reports", %{
      conn: conn,
      admin: admin,
      user: user,
      reported: reported,
      report: earlier
    } do
      {:ok, post} =
        Hybridsocial.Social.Posts.create_post(reported.id, %{
          "content" => "reported body",
          "spoiler_text" => "cw"
        })

      {:ok, report} =
        Moderation.create_report(user.id, %{
          "reported_id" => reported.id,
          "target_type" => "post",
          "target_id" => post.id,
          "category" => "harassment",
          "description" => "why"
        })

      {:ok, _} = Moderation.resolve_report(report.id, admin.id, "warned")

      data =
        get(conn, "/api/v1/admin/reports/#{report.id}")
        |> json_response(200)
        |> Map.fetch!("data")

      assert data["description"] == "why"
      assert data["action_taken"] == "warned"
      assert data["target_post"]["id"] == post.id
      assert data["target_post"]["spoiler_text"] == "cw"
      assert data["target_post"]["author"]["id"] == reported.id
      assert [%{"action" => "report.resolved"}] = data["audit_log"]
      assert [%{"id" => related_id}] = data["related_reports"]
      assert related_id == earlier.id
      assert data["reported_open_reports"] == 1
    end

    test "a closed report can't be closed or assigned again", %{conn: conn, report: report} do
      assert json_response(post(conn, "/api/v1/admin/reports/#{report.id}/dismiss"), 200)

      assert %{"error" => "report.already_closed"} =
               json_response(post(conn, "/api/v1/admin/reports/#{report.id}/resolve"), 409)

      assert %{"error" => "report.already_closed"} =
               json_response(post(conn, "/api/v1/admin/reports/#{report.id}/assign", %{}), 409)

      # One audit entry per action, not two (the controller used to log again).
      assert [_] = Moderation.report_audit_log(report.id)
    end

    test "resolving an investigating post report still drops the post's open count", %{
      admin: admin,
      user: user,
      reported: reported
    } do
      {:ok, post} = Hybridsocial.Social.Posts.create_post(reported.id, %{"content" => "x"})

      {:ok, report} =
        Moderation.create_report(user.id, %{
          "reported_id" => reported.id,
          "target_type" => "post",
          "target_id" => post.id,
          "category" => "spam"
        })

      {:ok, _} = Moderation.assign_report(report.id, admin.id)
      {:ok, _} = Moderation.resolve_report(report.id, admin.id, "resolved")

      assert Hybridsocial.Repo.get!(Hybridsocial.Social.Post, post.id).open_report_count == 0
    end

    test "GET /admin/posts/:id works for a reported post", %{
      conn: conn,
      user: user,
      reported: reported
    } do
      {:ok, post} = Hybridsocial.Social.Posts.create_post(reported.id, %{"content" => "x"})

      {:ok, _} =
        Moderation.create_report(user.id, %{
          "reported_id" => reported.id,
          "target_type" => "post",
          "target_id" => post.id,
          "category" => "spam",
          "description" => "note"
        })

      assert %{"reports" => [%{"comment" => "note"}]} =
               get(conn, "/api/v1/admin/posts/#{post.id}") |> json_response(200) |> unwrap_data()
    end
  end

  defp unwrap_data(%{"data" => data}), do: data
  defp unwrap_data(body), do: body

  describe "moderator access" do
    setup %{conn: conn} do
      moderator = create_user("mod1", "mod1@test.com") |> make_moderator()
      user = create_user("user2", "user2@test.com")
      reported = create_user("reported2", "reported2@test.com")

      {:ok, report} =
        Moderation.create_report(user.id, %{
          "reported_id" => reported.id,
          "category" => "spam",
          "description" => "Test report"
        })

      %{conn: admin_conn(conn, moderator), moderator: moderator, report: report}
    end

    test "moderator can view reports", %{conn: conn} do
      conn = get(conn, "/api/v1/admin/reports")
      assert %{"data" => _} = json_response(conn, 200)
    end

    test "moderator can view audit log", %{conn: conn, moderator: moderator} do
      Moderation.log(moderator.id, "test.action", nil, nil, %{})
      conn = get(conn, "/api/v1/admin/audit_log")
      assert %{"data" => _} = json_response(conn, 200)
    end

    test "moderator cannot manage federation", %{conn: conn} do
      conn = get(conn, "/api/v1/admin/banned_domains")
      assert json_response(conn, 403)["error"] == "permission.denied"
    end

    test "moderator cannot manage relays", %{conn: conn} do
      conn = get(conn, "/api/v1/admin/relays")
      assert json_response(conn, 403)["error"] == "permission.denied"
    end
  end

  describe "admin audit log" do
    setup %{conn: conn} do
      admin = create_user("admin2", "admin2@test.com") |> make_admin()
      Moderation.log(admin.id, "test.action", nil, nil, %{})

      %{conn: admin_conn(conn, admin), admin: admin}
    end

    test "GET /api/v1/admin/audit_log lists entries", %{conn: conn} do
      conn = get(conn, "/api/v1/admin/audit_log")
      assert %{"data" => data} = json_response(conn, 200)
      assert length(data) >= 1
    end
  end

  describe "admin accounts" do
    setup %{conn: conn} do
      admin = create_user("admin3", "admin3@test.com") |> make_admin()
      user = create_user("target1", "target1@test.com")

      %{conn: admin_conn(conn, admin), admin: admin, user: user}
    end

    test "GET /api/v1/admin/accounts lists accounts", %{conn: conn} do
      conn = get(conn, "/api/v1/admin/accounts")
      assert %{"data" => data} = json_response(conn, 200)
      assert length(data) >= 2
    end

    test "POST /api/v1/admin/accounts/:id/action suspends user", %{conn: conn, user: user} do
      conn = post(conn, "/api/v1/admin/accounts/#{user.id}/action", %{"action" => "suspend"})
      assert %{"data" => data} = json_response(conn, 200)
      assert data["is_suspended"] == true
    end

    test "POST /api/v1/admin/accounts/:id/action unsuspends user", %{conn: conn, user: user} do
      # First suspend
      post(conn, "/api/v1/admin/accounts/#{user.id}/action", %{"action" => "suspend"})
      # Then unsuspend
      conn = post(conn, "/api/v1/admin/accounts/#{user.id}/action", %{"action" => "unsuspend"})
      assert %{"data" => data} = json_response(conn, 200)
      assert data["is_suspended"] == false
    end

    test "POST /api/v1/admin/accounts/:id/action warns user", %{conn: conn, user: user} do
      conn =
        post(conn, "/api/v1/admin/accounts/#{user.id}/action", %{
          "action" => "warn",
          "reason" => "Violation"
        })

      assert %{"data" => _data, "message" => "account.warned"} = json_response(conn, 200)
    end

    test "PUT /api/v1/admin/users/:id/profile clears avatar and header", %{conn: conn, user: user} do
      # Give the user an avatar + header, then null them via the endpoint.
      {:ok, _} =
        Hybridsocial.Accounts.admin_update_identity(user, %{
          "avatar_url" => "https://cdn.example/a.png",
          "header_url" => "https://cdn.example/h.png"
        })

      conn =
        put(conn, "/api/v1/admin/users/#{user.id}/profile", %{
          "avatar_url" => nil,
          "header_url" => nil
        })

      assert %{"data" => data} = json_response(conn, 200)
      assert data["avatar_url"] == nil
      assert data["header_url"] == nil

      reloaded = Hybridsocial.Accounts.get_identity(user.id)
      assert reloaded.avatar_url == nil
      assert reloaded.header_url == nil
    end
  end

  describe "admin content filters" do
    setup %{conn: conn} do
      admin = create_user("admin4", "admin4@test.com") |> make_admin()

      %{conn: admin_conn(conn, admin), admin: admin}
    end

    test "POST /api/v1/admin/content_filters creates a filter", %{conn: conn} do
      params = %{"type" => "word", "pattern" => "badword", "action" => "reject"}
      conn = post(conn, "/api/v1/admin/content_filters", params)
      assert %{"data" => data} = json_response(conn, 201)
      assert data["pattern"] == "badword"
    end

    test "GET /api/v1/admin/content_filters lists filters", %{conn: conn} do
      Moderation.create_filter(%{"type" => "word", "pattern" => "bad", "action" => "reject"})

      conn = get(conn, "/api/v1/admin/content_filters")
      assert %{"data" => data} = json_response(conn, 200)
      assert length(data) == 1
    end

    test "DELETE /api/v1/admin/content_filters/:id deletes a filter", %{conn: conn} do
      {:ok, filter} =
        Moderation.create_filter(%{"type" => "word", "pattern" => "bad", "action" => "reject"})

      conn = delete(conn, "/api/v1/admin/content_filters/#{filter.id}")
      assert json_response(conn, 200)["message"] == "filter.deleted"
    end
  end

  describe "admin banned domains" do
    setup %{conn: conn} do
      admin = create_user("admin5", "admin5@test.com") |> make_admin()

      %{conn: admin_conn(conn, admin), admin: admin}
    end

    test "POST /api/v1/admin/banned_domains bans a domain", %{conn: conn} do
      params = %{"domain" => "spam.com", "type" => "email", "reason" => "Spam"}
      conn = post(conn, "/api/v1/admin/banned_domains", params)
      assert %{"data" => data} = json_response(conn, 201)
      assert data["domain"] == "spam.com"
    end

    test "GET /api/v1/admin/banned_domains lists banned domains", %{conn: conn, admin: admin} do
      Moderation.ban_domain("spam.com", "email", "reason", admin.id)

      conn = get(conn, "/api/v1/admin/banned_domains")
      assert %{"data" => data} = json_response(conn, 200)
      assert length(data) == 1
    end

    test "DELETE /api/v1/admin/banned_domains/:domain unbans a domain", %{
      conn: conn,
      admin: admin
    } do
      Moderation.ban_domain("spam.com", "email", "reason", admin.id)

      conn = delete(conn, "/api/v1/admin/banned_domains/spam.com")
      assert json_response(conn, 200)["message"] == "domain.unbanned"
    end
  end

  describe "non-admin access" do
    test "returns 403 for non-admin users", %{conn: conn} do
      user = create_user("regular1", "regular1@test.com")
      conn = admin_conn(conn, user)

      conn = get(conn, "/api/v1/admin/reports")
      assert json_response(conn, 403)["error"] == "auth.forbidden"
    end

    test "returns 401 for unauthenticated users", %{conn: conn} do
      conn = get(conn, "/api/v1/admin/reports")
      assert json_response(conn, 401)["error"] == "auth.unauthorized"
    end
  end

  describe "federation dead letters + delivery kill switch" do
    setup %{conn: conn} do
      admin = create_user("fedadmin", "fedadmin@test.com") |> make_admin()

      for _ <- 1..3 do
        %Hybridsocial.Federation.Delivery{}
        |> Hybridsocial.Federation.Delivery.changeset(%{
          activity_id: "https://local.test/activities/#{System.unique_integer([:positive])}",
          activity_type: "Create",
          target_inbox: "https://gone.example/users/x/inbox",
          status: "failed"
        })
        |> Hybridsocial.Repo.insert!()
      end

      %{conn: admin_conn(conn, admin)}
    end

    test "GET dead_letters reports whole-queue counts per domain", %{conn: conn} do
      conn = get(conn, "/api/v1/admin/federation/dead_letters")
      assert %{"total" => 3, "by_domain" => by_domain} = json_response(conn, 200)
      assert [%{"domain" => "gone.example", "count" => 3}] = by_domain
    end

    test "POST dead_letters/drop_domain clears the whole domain", %{conn: conn} do
      conn =
        post(conn, "/api/v1/admin/federation/dead_letters/drop_domain", %{domain: "gone.example"})

      assert %{"dropped" => 3} = json_response(conn, 200)
      assert Hybridsocial.Repo.aggregate(Hybridsocial.Federation.Delivery, :count) == 0
    end

    test "disabling delivery drops the queue and blocks further attempts", %{conn: conn} do
      conn =
        post(conn, "/api/v1/admin/federation/delivery_disabled", %{
          domain: "gone.example",
          reason: "instance shut down",
          drop_dead_letters: true
        })

      assert %{"delivery_disabled" => true, "dropped" => 3} = json_response(conn, 200)
      refute Hybridsocial.Federation.CircuitBreaker.allow?("https://gone.example/users/x/inbox")
      assert Hybridsocial.Repo.aggregate(Hybridsocial.Federation.Delivery, :count) == 0
    end

    test "the disabled list round-trips through enable", %{conn: conn} do
      post(conn, "/api/v1/admin/federation/delivery_disabled", %{domain: "gone.example"})

      conn2 = get(conn, "/api/v1/admin/federation/delivery_disabled")
      assert %{"data" => [%{"domain" => "gone.example"}]} = json_response(conn2, 200)

      conn3 = delete(conn, "/api/v1/admin/federation/delivery_disabled/gone.example")
      assert %{"delivery_disabled" => false} = json_response(conn3, 200)
      assert Hybridsocial.Federation.CircuitBreaker.allow?("https://gone.example/users/x/inbox")
    end

    test "a non-admin cannot stop delivery", %{conn: _conn} do
      user = create_user("fednobody", "fednobody@test.com")

      conn =
        build_conn()
        |> auth_conn(user)
        |> post("/api/v1/admin/federation/delivery_disabled", %{domain: "gone.example"})

      assert json_response(conn, 403)
      refute Hybridsocial.Federation.CircuitBreaker.delivery_disabled?("gone.example")
    end
  end

  describe "permission-based access control" do
    test "community_manager cannot access reports", %{conn: conn} do
      cm = create_user("cm1", "cm1@test.com")
      {:ok, _} = RBAC.assign_role(cm.id, "community_manager", cm.id)
      enable_otp(cm)
      conn = admin_conn(conn, cm)

      conn = get(conn, "/api/v1/admin/reports")
      assert json_response(conn, 403)["error"] == "permission.denied"
    end

    test "community_manager can access content filters", %{conn: conn} do
      cm = create_user("cm2", "cm2@test.com")
      {:ok, _} = RBAC.assign_role(cm.id, "community_manager", cm.id)
      enable_otp(cm)
      conn = admin_conn(conn, cm)

      conn = get(conn, "/api/v1/admin/content_filters")
      assert %{"data" => _} = json_response(conn, 200)
    end
  end

  describe "admin account content (issue #166)" do
    setup %{conn: conn} do
      admin = create_user("adm_content", "adm_content@test.com") |> make_admin()
      user = create_user("usr_content", "usr_content@test.com")
      %{conn: admin_conn(conn, admin), user: user}
    end

    defp mk(identity, attrs) do
      {:ok, post} =
        Hybridsocial.Social.Posts.create_post(
          identity.id,
          Map.merge(%{"content" => "x", "visibility" => "public"}, attrs)
        )

      post
    end

    test "counts split posts, replies and media", %{conn: conn, user: user} do
      parent = mk(user, %{"content" => "top level"})
      mk(user, %{"content" => "another top level"})
      mk(user, %{"content" => "a reply", "parent_id" => parent.id})

      with_media = mk(user, %{"content" => "has media"})

      Hybridsocial.Repo.insert!(%Hybridsocial.Media.MediaFile{
        identity_id: user.id,
        post_id: with_media.id,
        content_type: "image/png",
        file_size: 1_000,
        storage_path: "test/#{with_media.id}.png",
        width: 800,
        height: 600
      })

      body = json_response(get(conn, "/api/v1/admin/users/#{user.id}"), 200)

      assert body["post_count"] == 3
      assert body["reply_count"] == 1
      assert body["media_count"] == 1
    end

    test "statuses tabs return posts, replies and media separately", %{conn: conn, user: user} do
      parent = mk(user, %{"content" => "top level"})
      reply = mk(user, %{"content" => "a reply", "parent_id" => parent.id})

      posts = json_response(get(conn, "/api/v1/admin/users/#{user.id}/statuses?type=posts"), 200)
      ids = Enum.map(posts, & &1["id"])
      assert parent.id in ids
      refute reply.id in ids

      replies =
        json_response(get(conn, "/api/v1/admin/users/#{user.id}/statuses?type=replies"), 200)

      reply_ids = Enum.map(replies, & &1["id"])
      assert reply.id in reply_ids
      refute parent.id in reply_ids
    end

    test "NEVER exposes direct-visibility statuses (those are DMs)", %{conn: conn, user: user} do
      public_post = mk(user, %{"content" => "public"})
      dm = mk(user, %{"content" => "a private message", "visibility" => "direct"})

      for type <- ["posts", "replies", "media", "anything"] do
        body =
          json_response(get(conn, "/api/v1/admin/users/#{user.id}/statuses?type=#{type}"), 200)

        refute dm.id in Enum.map(body, & &1["id"]),
               "direct-visibility status leaked into the #{type} tab"
      end

      assert public_post.id in Enum.map(
               json_response(get(conn, "/api/v1/admin/users/#{user.id}/statuses"), 200),
               & &1["id"]
             )

      # ...and the counts don't include it either.
      detail = json_response(get(conn, "/api/v1/admin/users/#{user.id}"), 200)
      assert detail["post_count"] == 1
    end

    test "requires the users.view permission", %{user: user} do
      stranger = create_user("nosy", "nosy@test.com")

      conn =
        auth_conn(Phoenix.ConnTest.build_conn(), stranger)
        |> get("/api/v1/admin/users/#{user.id}/statuses")

      assert conn.status in [401, 403]
    end
  end

  describe "admin translation config" do
    setup %{conn: conn} do
      # Config.Store isn't started in the test env, so start one per test and
      # share the sandbox connection so it can read/write the settings table.
      Ecto.Adapters.SQL.Sandbox.mode(Hybridsocial.Repo, {:shared, self()})
      start_supervised!(Hybridsocial.Config.Store)

      admin = create_user("tcfg_admin", "tcfg_admin@test.com") |> make_admin()
      %{conn: admin_conn(conn, admin), admin: admin}
    end

    test "is disabled by default and reports no key", %{conn: conn} do
      body = json_response(get(conn, "/api/v1/admin/translation"), 200)

      assert body["backend"] == "none"
      assert body["api_key"] == ""
    end

    test "round-trips the backend and url", %{conn: conn} do
      conn =
        put(conn, "/api/v1/admin/translation", %{
          "backend" => "libretranslate",
          "api_url" => "https://lt.internal.example"
        })

      body = json_response(conn, 200)
      assert body["backend"] == "libretranslate"
      assert body["api_url"] == "https://lt.internal.example"
      assert Hybridsocial.Config.get("translation_backend") == "libretranslate"
    end

    test "never returns the raw api key", %{conn: conn} do
      secret = "super-secret-translation-key"
      put(conn, "/api/v1/admin/translation", %{"api_key" => secret})

      body = json_response(get(conn, "/api/v1/admin/translation"), 200)

      refute body["api_key"] == secret
      assert body["api_key"] =~ "****"
      # The real value is still stored — only the response is masked.
      assert Hybridsocial.Config.get("translation_api_key") == secret
    end

    # Saving the form without touching the key field sends the mask back.
    # Writing that through would silently destroy the admin's real key.
    test "saving a masked key leaves the stored secret intact", %{conn: conn} do
      secret = "super-secret-translation-key"
      put(conn, "/api/v1/admin/translation", %{"api_key" => secret})

      masked = json_response(get(conn, "/api/v1/admin/translation"), 200)["api_key"]
      put(conn, "/api/v1/admin/translation", %{"api_key" => masked, "backend" => "deepl"})

      assert Hybridsocial.Config.get("translation_api_key") == secret
      assert Hybridsocial.Config.get("translation_backend") == "deepl"
    end

    test "an explicit new key replaces the old one", %{conn: conn} do
      put(conn, "/api/v1/admin/translation", %{"api_key" => "old-key-value"})
      put(conn, "/api/v1/admin/translation", %{"api_key" => "new-key-value"})

      assert Hybridsocial.Config.get("translation_api_key") == "new-key-value"
    end

    test "requires the settings.manage permission" do
      stranger = create_user("tcfg_nosy", "tcfg_nosy@test.com")
      conn = auth_conn(Phoenix.ConnTest.build_conn(), stranger)

      assert get(conn, "/api/v1/admin/translation").status in [401, 403]
      assert put(conn, "/api/v1/admin/translation", %{"backend" => "deepl"}).status in [401, 403]
    end
  end

  # #167: pages and groups are Identity rows, so they were always in this list.
  # The filter is what makes them findable.
  describe "admin account list — identity type filter" do
    setup %{conn: conn} do
      admin = create_user("at_admin", "at_admin@test.com") |> make_admin()
      owner = create_user("at_owner", "at_owner@test.com")

      {:ok, page} =
        Hybridsocial.Pages.create_page(owner.id, %{
          "handle" => "at_page",
          "display_name" => "A Page",
          "category" => "tech"
        })

      {:ok, group} =
        Hybridsocial.Groups.create_group(owner.id, %{
          "name" => "A Group",
          "handle" => "at_group",
          "visibility" => "public",
          "join_policy" => "open"
        })

      %{conn: admin_conn(conn, admin), page: page, group: group, owner: owner}
    end

    defp listed_types(conn, query) do
      conn
      |> get("/api/v1/admin/users" <> query)
      |> json_response(200)
      |> Map.fetch!("data")
      |> Enum.map(& &1["type"])
      |> Enum.uniq()
      |> Enum.sort()
    end

    test "unfiltered still returns every identity type", %{conn: conn} do
      types = listed_types(conn, "")
      assert "user" in types
      assert "page" in types
      assert "group" in types
    end

    # The API says "page"; the column says "organization". The filter has to
    # speak the API's language or admins can't use what they see.
    test "type=page returns only pages", %{conn: conn, page: page} do
      assert listed_types(conn, "?type=page") == ["page"]

      ids =
        conn
        |> get("/api/v1/admin/users?type=page")
        |> json_response(200)
        |> Map.fetch!("data")
        |> Enum.map(& &1["id"])

      assert page.id in ids
    end

    test "type=group returns only groups", %{conn: conn, group: group} do
      assert listed_types(conn, "?type=group") == ["group"]

      ids =
        conn
        |> get("/api/v1/admin/users?type=group")
        |> json_response(200)
        |> Map.fetch!("data")
        |> Enum.map(& &1["id"])

      assert group.identity_id in ids
    end

    test "type=user excludes pages and groups", %{conn: conn} do
      assert listed_types(conn, "?type=user") == ["user"]
    end

    test "an unrecognised type is ignored rather than erroring", %{conn: conn} do
      assert length(listed_types(conn, "?type=nonsense")) > 1
    end

    test "the detail view works for a page", %{conn: conn, page: page} do
      body = json_response(get(conn, "/api/v1/admin/users/#{page.id}"), 200)
      data = body["data"] || body

      assert data["type"] == "page"
      assert is_integer(data["post_count"])
      assert is_integer(data["followers_count"])
    end

    test "the detail view works for a group", %{conn: conn, group: group} do
      body = json_response(get(conn, "/api/v1/admin/users/#{group.identity_id}"), 200)
      data = body["data"] || body

      assert data["type"] == "group"
    end

    test "the filter still requires users.view", %{page: _page} do
      stranger = create_user("at_nosy", "at_nosy@test.com")

      conn =
        auth_conn(Phoenix.ConnTest.build_conn(), stranger)
        |> get("/api/v1/admin/users?type=page")

      assert conn.status in [401, 403]
    end
  end

  # #167 item 2: a page's or group's followers were visible only as a count.
  describe "admin followers view" do
    setup %{conn: conn} do
      admin = create_user("fv_admin", "fv_admin@test.com") |> make_admin()
      owner = create_user("fv_owner", "fv_owner@test.com")
      fan = create_user("fv_fan", "fv_fan@test.com")

      {:ok, page} =
        Hybridsocial.Pages.create_page(owner.id, %{
          "handle" => "fv_page",
          "display_name" => "Followed Page",
          "category" => "tech"
        })

      {:ok, _} = Hybridsocial.Social.follow(fan.id, page.id)

      %{conn: admin_conn(conn, admin), page: page, fan: fan, owner: owner}
    end

    test "lists a page's followers", %{conn: conn, page: page, fan: fan} do
      data =
        conn
        |> get("/api/v1/admin/users/#{page.id}/followers")
        |> json_response(200)
        |> Map.fetch!("data")

      assert fan.id in Enum.map(data, & &1["id"])
    end

    test "an admin can sever a follow", %{conn: conn, page: page, fan: fan} do
      assert json_response(
               delete(conn, "/api/v1/admin/users/#{page.id}/followers/#{fan.id}"),
               200
             )

      data =
        conn
        |> get("/api/v1/admin/users/#{page.id}/followers")
        |> json_response(200)
        |> Map.fetch!("data")

      refute fan.id in Enum.map(data, & &1["id"])
    end

    test "removing a follower is audited", %{conn: conn, page: page, fan: fan} do
      delete(conn, "/api/v1/admin/users/#{page.id}/followers/#{fan.id}")

      entry =
        Hybridsocial.Repo.get_by(Hybridsocial.Moderation.AuditLog,
          action: "account.remove_follower"
        )

      assert entry
      assert entry.target_id == page.id
      assert entry.details["follower_id"] == fan.id
    end

    # Viewing is a read; severing someone's follow is a moderation action.
    test "viewing needs users.view, removing needs users.moderate", %{page: page, fan: fan} do
      stranger = create_user("fv_nosy", "fv_nosy@test.com")
      c = auth_conn(Phoenix.ConnTest.build_conn(), stranger)

      assert get(c, "/api/v1/admin/users/#{page.id}/followers").status in [401, 403]

      assert delete(
               auth_conn(Phoenix.ConnTest.build_conn(), stranger),
               "/api/v1/admin/users/#{page.id}/followers/#{fan.id}"
             ).status in [401, 403]
    end
  end

  describe "admin group members view" do
    setup %{conn: conn} do
      admin = create_user("gm_admin", "gm_admin@test.com") |> make_admin()
      owner = create_user("gm_owner", "gm_owner@test.com")
      member = create_user("gm_member", "gm_member@test.com")

      {:ok, group} =
        Hybridsocial.Groups.create_group(owner.id, %{
          "name" => "Admin Viewed",
          "handle" => "gm_group",
          "visibility" => "public",
          "join_policy" => "open"
        })

      {:ok, _} = Hybridsocial.Groups.join_group(group.id, member.id)

      %{conn: admin_conn(conn, admin), group: group, owner: owner, member: member}
    end

    # The admin views hold the *identity* id; a group's own primary key isn't
    # reachable from there, which is what get_group_by_identity/1 bridges.
    test "lists members when addressed by the group's identity id", %{
      conn: conn,
      group: group,
      owner: owner,
      member: member
    } do
      data =
        conn
        |> get("/api/v1/admin/users/#{group.identity_id}/group_members")
        |> json_response(200)
        |> Map.fetch!("data")

      ids = Enum.map(data, & &1["account"]["id"])
      assert owner.id in ids
      assert member.id in ids

      owner_row = Enum.find(data, &(&1["account"]["id"] == owner.id))
      assert owner_row["role"] == "owner"
    end

    test "404s for an identity that isn't a group", %{conn: conn, member: member} do
      assert json_response(get(conn, "/api/v1/admin/users/#{member.id}/group_members"), 404)
    end

    test "requires users.view", %{group: group} do
      stranger = create_user("gm_nosy", "gm_nosy@test.com")

      conn =
        auth_conn(Phoenix.ConnTest.build_conn(), stranger)
        |> get("/api/v1/admin/users/#{group.identity_id}/group_members")

      assert conn.status in [401, 403]
    end
  end

  describe "hashtag blocks" do
    test "an admin can block, list and unblock a hashtag", %{conn: conn} do
      admin = create_admin("tagblock_admin")
      conn = admin_conn(conn, admin)

      created =
        conn
        |> post("/api/v1/admin/hashtag_blocks", %{"name" => "#Spam", "action" => "hide"})
        |> json_response(201)

      assert %{"name" => "spam", "action" => "hide", "id" => id} = created["data"]

      assert %{"data" => [%{"id" => ^id}]} =
               conn |> get("/api/v1/admin/hashtag_blocks") |> json_response(200)

      assert conn |> delete("/api/v1/admin/hashtag_blocks/#{id}") |> json_response(200)
      assert Moderation.list_blocked_hashtags() == []
    end

    test "an invalid tag returns a validation error", %{conn: conn} do
      admin = create_admin("tagblock_invalid")

      assert %{"error" => "validation.failed"} =
               conn
               |> admin_conn(admin)
               |> post("/api/v1/admin/hashtag_blocks", %{"name" => "two words"})
               |> json_response(422)
    end

    test "deleting an unknown or malformed id returns 404", %{conn: conn} do
      conn = admin_conn(conn, create_admin("tagblock_missing"))

      for id <- [Ecto.UUID.generate(), "not-a-uuid"] do
        assert conn |> delete("/api/v1/admin/hashtag_blocks/#{id}") |> json_response(404)
      end
    end

    test "a regular user can't manage hashtag blocks", %{conn: conn} do
      user = create_user("tagblock_user")

      response =
        conn
        |> auth_conn(user)
        |> post("/api/v1/admin/hashtag_blocks", %{"name" => "spam"})

      assert response.status in [401, 403]
      assert Moderation.list_blocked_hashtags() == []
    end
  end

  describe "instance purge" do
    alias Hybridsocial.Accounts.Identity
    alias Hybridsocial.Social.{Post, Posts}

    import Ecto.Query

    defp set_actor(identity, url, is_local) do
      {1, _} =
        Hybridsocial.Repo.update_all(from(i in Identity, where: i.id == ^identity.id),
          set: [ap_actor_url: url, is_local: is_local]
        )

      identity
    end

    setup %{conn: conn} do
      remote =
        "purge_remote" |> create_user() |> set_actor("https://evil.example/users/x", false)

      imported =
        "purge_imported" |> create_user() |> set_actor("https://evil.example/users/y", true)

      {:ok, remote_post} = Posts.create_post(remote.id, %{"content" => "spam"})
      {:ok, imported_post} = Posts.create_post(imported.id, %{"content" => "ours"})
      {:ok, _} = Hybridsocial.Federation.set_instance_policy("evil.example", "suspend", nil, nil)

      %{
        conn: admin_conn(conn, create_admin("purge_admin")),
        remote_post: remote_post,
        imported_post: imported_post
      }
    end

    # The admin modal reads these exact keys under `data`: a mismatch crashes it.
    test "preview returns the counts without removing anything", ctx do
      assert %{
               "data" => %{
                 "identities_affected" => 1,
                 "posts_removed" => 1,
                 "follows_removed" => 0,
                 "reactions_removed" => 0,
                 "boosts_removed" => 0,
                 "dry_run" => true
               }
             } =
               ctx.conn
               |> post("/api/v1/admin/instance_policies/evil.example/purge_preview")
               |> json_response(200)

      assert is_nil(Hybridsocial.Repo.get!(Post, ctx.remote_post.id).deleted_at)
    end

    test "purge removes remote content but not imported local accounts'", ctx do
      assert %{"data" => %{"posts_removed" => 1, "dry_run" => false}} =
               ctx.conn
               |> post("/api/v1/admin/instance_policies/evil.example/purge")
               |> json_response(200)

      refute is_nil(Hybridsocial.Repo.get!(Post, ctx.remote_post.id).deleted_at)
      assert is_nil(Hybridsocial.Repo.get!(Post, ctx.imported_post.id).deleted_at)
    end
  end

  describe "account list paging" do
    import Ecto.Query

    alias Hybridsocial.Accounts
    alias Hybridsocial.Accounts.Identity
    alias Hybridsocial.Repo

    setup %{conn: conn} do
      %{conn: admin_conn(conn, create_admin("page_admin"))}
    end

    defp list(conn, params) do
      conn |> get("/api/v1/admin/users", params) |> json_response(200)
    end

    defp handles(body), do: Enum.map(body["data"], & &1["handle"])

    defp make_remote(identity, url) do
      {1, _} =
        Repo.update_all(from(i in Identity, where: i.id == ^identity.id),
          set: [is_local: false, ap_actor_url: url]
        )
    end

    test "returns one page and the full total", %{conn: conn} do
      for n <- 1..5, do: create_user("page_user#{n}")
      total = Repo.aggregate(where(Identity, [i], is_nil(i.deleted_at)), :count)

      first = list(conn, %{"limit" => "2", "offset" => "0"})
      second = list(conn, %{"limit" => "2", "offset" => "2"})

      assert length(first["data"]) == 2
      assert first["total"] == total
      assert second["offset"] == 2
      assert MapSet.disjoint?(MapSet.new(handles(first)), MapSet.new(handles(second)))
    end

    test "caps the page size when none is sensible", %{conn: conn} do
      for n <- 1..3, do: create_user("cap_user#{n}")

      assert length(list(conn, %{"limit" => "2"})["data"]) == 2
      assert list(conn, %{"limit" => "100000"})["limit"] <= 40
      assert list(conn, %{"offset" => "banana"})["offset"] == 0
    end

    test "searches handle and display name, treating wildcards literally", %{conn: conn} do
      create_user("findme_handle")
      other = create_user("other_person")

      {1, _} =
        Repo.update_all(from(i in Identity, where: i.id == ^other.id),
          set: [display_name: "Findme Display"]
        )

      assert handles(list(conn, %{"search" => "@FINDME"})) |> Enum.sort() ==
               ["findme_handle", "other_person"]

      assert handles(list(conn, %{"search" => "fi%me"})) == []
    end

    test "finds a remote account by domain and by user@domain", %{conn: conn} do
      remote = create_user("mangled_remote_1")
      make_remote(remote, "https://evil.example/users/bob")

      assert handles(list(conn, %{"search" => "evil.example"})) == ["bob"]
      assert handles(list(conn, %{"search" => "bob@evil.example"})) == ["bob"]
      assert handles(list(conn, %{"search" => "alice@evil.example"})) == []
    end

    test "a search for our own host doesn't match every local account", %{conn: conn} do
      create_user("local_only")
      host = URI.parse(HybridsocialWeb.Endpoint.url()).host

      assert handles(list(conn, %{"search" => host})) == []
    end

    test "finds an email by its exact address only", %{conn: conn} do
      create_user("mail_user", "mail_user@example.com")

      assert handles(list(conn, %{"search" => "MAIL_user@example.com"})) == ["mail_user"]
      assert handles(list(conn, %{"search" => "wrong@example.com"})) == []
    end

    test "filters by status, location, email state and type", %{conn: conn} do
      suspended = create_user("filter_suspended")
      {:ok, _} = Accounts.suspend_identity(suspended)
      remote = create_user("filter_remote")
      make_remote(remote, "https://far.example/users/farbob")
      create_unconfirmed_user("filter_unconfirmed")

      assert "filter_suspended" in handles(list(conn, %{"status" => "suspended"}))
      refute "filter_suspended" in handles(list(conn, %{"status" => "active"}))

      assert handles(list(conn, %{"local" => "false"})) == ["farbob"]
      refute "farbob" in handles(list(conn, %{"local" => "true"}))

      unverified = handles(list(conn, %{"email" => "unverified"}))
      assert "filter_unconfirmed" in unverified
      refute "farbob" in unverified
      refute "filter_suspended" in unverified

      assert list(conn, %{"type" => "group"})["data"] == []
    end

    test "sorts by an allowed column and ignores an unknown one", %{conn: conn} do
      create_user("aaa_sort")
      create_user("zzz_sort")

      assert handles(list(conn, %{"sort" => "handle", "dir" => "asc"})) |> hd() <
               handles(list(conn, %{"sort" => "handle", "dir" => "desc"})) |> hd()

      assert %{"data" => [_ | _]} = list(conn, %{"sort" => "private_key; drop table"})
    end

    test "pins to one id, and an invalid id finds nothing", %{conn: conn} do
      target = create_user("pinned_user")

      assert handles(list(conn, %{"id" => target.id})) == ["pinned_user"]
      assert list(conn, %{"id" => "not-a-uuid"})["total"] == 0
    end
  end

  describe "media hash bans" do
    @sha256 String.duplicate("ab", 32)

    # The admin tab reads the list and the created row from under `data`.
    test "creates and lists under data, normalizing the hash", %{conn: conn} do
      conn = admin_conn(conn, create_admin("hash_admin"))

      assert %{"data" => %{"id" => id, "hash" => @sha256}} =
               conn
               |> post("/api/v1/admin/media_hash_bans", %{
                 "hash" => " #{String.upcase(@sha256)} ",
                 "hash_type" => "sha256"
               })
               |> json_response(201)

      assert %{"data" => [%{"id" => ^id}]} =
               conn |> get("/api/v1/admin/media_hash_bans") |> json_response(200)

      assert Moderation.media_hash_banned?(@sha256)
    end

    test "rejects a value that could never match an upload", %{conn: conn} do
      assert conn
             |> admin_conn(create_admin("hash_invalid"))
             |> post("/api/v1/admin/media_hash_bans", %{
               "hash" => "not-a-hash",
               "hash_type" => "sha256"
             })
             |> json_response(422)
    end

    test "a duplicate returns a validation error, not a crash", %{conn: conn} do
      conn = admin_conn(conn, create_admin("hash_dup"))
      params = %{"hash" => @sha256, "hash_type" => "sha256"}

      assert conn |> post("/api/v1/admin/media_hash_bans", params) |> json_response(201)
      assert conn |> post("/api/v1/admin/media_hash_bans", params) |> json_response(422)
    end
  end

  describe "moderation queue stats" do
    # The admin Queue tab renders all four, and crashed when one was missing.
    test "reports every status, even with an empty queue", %{conn: conn} do
      assert %{
               "data" => %{"pending" => 0, "approved" => 0, "rejected" => 0, "escalated" => 0}
             } =
               conn
               |> admin_conn(create_admin("queue_stats_admin"))
               |> get("/api/v1/admin/moderation_queue/stats")
               |> json_response(200)
    end
  end

  describe "posting limits" do
    alias Hybridsocial.Accounts.Identity
    alias Hybridsocial.Repo

    setup %{conn: conn} do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
      start_supervised!(Hybridsocial.Config.Store)

      admin = create_admin("limits_admin")
      target = create_user("limits_target")
      %{conn: admin_conn(conn, admin), plain: conn, target: target}
    end

    test "staff can set, read back and clear an account's limits", %{conn: conn, target: target} do
      path = "/api/v1/admin/users/#{target.id}/post_limits"

      body = conn |> put(path, %{"per_hour" => 2, "per_day" => 10}) |> json_response(200)
      assert body["post_limits"] == %{"per_hour" => 2, "per_day" => 10}
      assert Repo.get!(Identity, target.id).post_limits == %{"per_hour" => 2, "per_day" => 10}

      user = conn |> get("/api/v1/admin/users/#{target.id}") |> json_response(200)
      assert user["post_limits"] == %{"per_hour" => 2, "per_day" => 10}

      body = conn |> put(path, %{"per_hour" => nil}) |> json_response(200)
      assert body["post_limits"] == %{}
    end

    test "0 is accepted, and means exempt", %{conn: conn, target: target} do
      path = "/api/v1/admin/users/#{target.id}/post_limits"

      assert conn |> put(path, %{"per_day" => 0}) |> json_response(200)

      assert %{day: 0} =
               Hybridsocial.Social.PostRateLimit.limits_for(Repo.get!(Identity, target.id))
    end

    test "invalid values are refused and change nothing", %{conn: conn, target: target} do
      path = "/api/v1/admin/users/#{target.id}/post_limits"

      for bad <- [-1, "5", 1.5, %{}] do
        assert conn |> put(path, %{"per_day" => bad}) |> json_response(422)
      end

      assert Repo.get!(Identity, target.id).post_limits == %{}
    end

    test "an unknown account is a 404", %{conn: conn} do
      path = "/api/v1/admin/users/#{Ecto.UUID.generate()}/post_limits"
      assert conn |> put(path, %{"per_day" => 1}) |> json_response(404)
    end

    test "a regular user can't set limits", %{plain: conn, target: target} do
      conn = auth_conn(conn, create_user("limits_plain"))

      response = put(conn, "/api/v1/admin/users/#{target.id}/post_limits", %{"per_day" => 0})

      assert response.status in [401, 403]
      assert Repo.get!(Identity, target.id).post_limits == %{}
    end

    test "defaults reflect the settings, which the settings API can write", %{conn: conn} do
      assert %{"user" => %{"minute" => 6, "hour" => 20, "day" => 100}} =
               conn |> get("/api/v1/admin/post_limits/defaults") |> json_response(200)

      conn
      |> put("/api/v1/admin/settings", %{
        "settings" => [%{"key" => "user_posts_per_hour", "value" => 12}]
      })
      |> json_response(200)

      assert %{"user" => %{"hour" => 12}} =
               conn |> get("/api/v1/admin/post_limits/defaults") |> json_response(200)
    end
  end
end
