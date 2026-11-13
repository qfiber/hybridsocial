defmodule HybridsocialWeb.CrawlerControllerTest do
  # async: false because the Config.Store GenServer needs the shared DB
  # sandbox connection to read instance settings during crawler rendering.
  use HybridsocialWeb.ConnCase, async: false

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Hybridsocial.Repo, {:shared, self()})
    start_supervised!(Hybridsocial.Config.Store)
    :ok
  end

  import Ecto.Query, only: [from: 2]

  alias Hybridsocial.Accounts
  alias Hybridsocial.Repo
  alias Hybridsocial.Social.Posts

  @crawler_ua "facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)"
  @browser_ua "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Chrome"

  defp register(handle) do
    uniq = :erlang.unique_integer([:positive])

    {:ok, identity} =
      Accounts.register_user(%{
        "handle" => "#{handle}_#{uniq}",
        "email" => "#{handle}_#{uniq}@example.com",
        "display_name" => handle,
        "password" => "password1234567890",
        "password_confirmation" => "password1234567890"
      })

    identity
  end

  defp crawler_conn do
    build_conn() |> put_req_header("user-agent", @crawler_ua)
  end

  defp browser_conn do
    build_conn() |> put_req_header("user-agent", @browser_ua)
  end

  describe "GET /post/:id" do
    test "serves full OG for a public post to a crawler" do
      alice = register("alice_og")
      {:ok, post} = Posts.create_post(alice.id, %{"content" => "Hello, world — this is public"})

      conn = get(crawler_conn(), "/post/#{post.id}")
      body = response(conn, 200)

      assert body =~ ~s(property="og:title")
      assert body =~ ~s(property="og:description")
      assert body =~ ~s(property="og:image")
      assert body =~ ~s(property="og:type" content="article")
      assert body =~ "Hello, world"
      # Author name surfaces in og:title
      assert body =~ "alice_og"
    end

    test "serves placeholder OG for a private (followers-only) post" do
      alice = register("alice_priv")

      {:ok, post} =
        Posts.create_post(alice.id, %{
          "content" => "secret message",
          "visibility" => "followers"
        })

      conn = get(crawler_conn(), "/post/#{post.id}")
      body = response(conn, 200)

      assert body =~ "Private post on"
      refute body =~ "secret message"
    end

    test "returns 404 for unknown post id" do
      conn = get(crawler_conn(), "/post/#{Ecto.UUID.generate()}")
      assert response(conn, 404)
    end

    test "browser requests get a redirect shell, not OG content" do
      alice = register("alice_browser")
      {:ok, post} = Posts.create_post(alice.id, %{"content" => "public"})

      conn = get(browser_conn(), "/post/#{post.id}")
      body = response(conn, 200)

      refute body =~ ~s(property="og:title")
      assert body =~ "window.location.replace"
    end

    test "uses the configured instance name, not a hardcoded value" do
      alice = register("alice_instance")
      {:ok, post} = Posts.create_post(alice.id, %{"content" => "hi"})

      :ok = Hybridsocial.Config.set("instance_name", "MyCustomInstance")

      conn = get(crawler_conn(), "/post/#{post.id}")
      body = response(conn, 200)

      # Flaky in full-suite runs only (#266) and not yet reproducible on
      # demand: on failure, say what the store held and what was rendered.
      assert body =~ "MyCustomInstance", """
      instance name missing from the crawler page (#266)
        Config.get("instance_name") now: #{inspect(Hybridsocial.Config.get("instance_name"))}
        Config.Store alive: #{inspect(Process.whereis(Hybridsocial.Config.Store))}
        settings table: #{inspect(:ets.whereis(:hybridsocial_settings))}
        rendered title/site_name: #{inspect(Regex.scan(~r/<title>[^<]*<\/title>|og:site_name" content="[^"]*"/, body))}
      """
    end
  end

  describe "GET /@:handle" do
    test "serves full profile OG when allow_unfurl is true" do
      alice = register("alice_profile")

      conn = get(crawler_conn(), "/@#{alice.handle}")
      body = response(conn, 200)

      assert body =~ "alice_profile"
      assert body =~ ~s(property="og:type" content="profile")
    end

    test "serves placeholder OG when allow_unfurl is false" do
      alice = register("alice_optout")
      secret_bio = "my-highly-distinctive-secret-bio-xyz"
      secret_name = "Definitely Not In The URL Name"

      alice
      |> Ecto.Changeset.change(%{
        allow_unfurl: false,
        bio: secret_bio,
        display_name: secret_name
      })
      |> Repo.update!()

      conn = get(crawler_conn(), "/@#{alice.handle}")
      body = response(conn, 200)

      # Placeholder title and description — no display_name, no bio.
      assert body =~ ~s(og:title" content="User on)
      assert body =~ ~s(og:description" content="A member of)
      refute body =~ secret_bio
      refute body =~ secret_name
    end

    test "returns 404 for unknown handle" do
      conn = get(crawler_conn(), "/@definitelynotarealuser12345")
      assert response(conn, 404)
    end
  end

  describe "GET /sitemap.xml (index)" do
    test "returns a sitemapindex pointing at child sitemaps" do
      alice = register("smp_idx")
      {:ok, _post} = Posts.create_post(alice.id, %{"content" => "indexed"})

      conn = get(build_conn(), "/sitemap.xml")
      body = response(conn, 200)

      content_type = get_resp_header(conn, "content-type") |> hd()
      assert content_type =~ "application/xml"
      assert body =~ "<sitemapindex"
      assert body =~ "/sitemap/static"
      assert body =~ "/sitemap/posts/1"
      assert body =~ "/sitemap/profiles/1"
    end

    test "posts index entries reflect the actual post count" do
      # No posts at all → no /sitemap/posts/ entry in the index.
      conn = get(build_conn(), "/sitemap.xml")
      body = response(conn, 200)

      assert body =~ "/sitemap/static"
      refute body =~ "/sitemap/posts/"
    end
  end

  describe "GET /sitemap/static" do
    test "emits the static page URLs" do
      conn = get(build_conn(), "/sitemap/static")
      body = response(conn, 200)

      assert body =~ "<urlset"
      assert body =~ "/legal/about"
      assert body =~ "/legal/privacy"
      assert body =~ "/directory"
    end
  end

  describe "GET /sitemap/posts/:page" do
    test "returns page 1 with only public+local posts" do
      alice = register("smp_p_a")
      {:ok, public} = Posts.create_post(alice.id, %{"content" => "public hi"})

      {:ok, private} =
        Posts.create_post(alice.id, %{"content" => "shh", "visibility" => "followers"})

      conn = get(build_conn(), "/sitemap/posts/1")
      body = response(conn, 200)

      assert body =~ "<urlset"
      assert body =~ "/post/#{public.id}"
      refute body =~ "/post/#{private.id}"
    end

    test "page out of range returns an empty urlset (not 404)" do
      conn = get(build_conn(), "/sitemap/posts/999999")
      body = response(conn, 200)

      assert body =~ "<urlset"
      refute body =~ "<url>"
    end

    test "invalid page param normalizes to 1" do
      conn = get(build_conn(), "/sitemap/posts/not-a-number")
      assert response(conn, 200) =~ "<urlset"
    end
  end

  describe "GET /sitemap/profiles/:page" do
    test "lists discoverable+unfurl-allowed profiles" do
      alice = register("smp_pr_a")
      hidden = register("smp_pr_h")

      hidden
      |> Ecto.Changeset.change(%{allow_unfurl: false})
      |> Repo.update!()

      conn = get(build_conn(), "/sitemap/profiles/1")
      body = response(conn, 200)

      assert body =~ "/@#{alice.handle}"
      refute body =~ "/@#{hidden.handle}"
    end
  end

  describe "GET /robots.txt" do
    test "returns a robots.txt with the expected rules" do
      conn = get(build_conn(), "/robots.txt")
      body = response(conn, 200)

      assert body =~ "User-agent: *"
      assert body =~ "Allow: /post/"
      assert body =~ "Allow: /@"
      assert body =~ "Disallow: /messages"
      assert body =~ "Disallow: /settings"
      assert body =~ "Disallow: /admin"
      assert body =~ "Sitemap:"
    end
  end

  describe "public view and search indexing" do
    alias Hybridsocial.Accounts.{Identity, PublicProfile}

    defp set_identity(identity, fields) do
      identity |> Ecto.Changeset.change(fields) |> Repo.update!()
      Repo.get!(Identity, identity.id)
    end

    defp profile_meta(identity) do
      build_conn() |> get("/api/v1/og/profile/#{identity.handle}") |> json_response(200)
    end

    defp post_meta(post),
      do: build_conn() |> get("/api/v1/og/post/#{post.id}") |> json_response(200)

    defp public_post(identity, attrs \\ %{}) do
      {:ok, post} =
        Posts.create_post(identity.id, Map.merge(%{"content" => "<b>Visible</b> text"}, attrs))

      post
    end

    defp sitemap(path), do: build_conn() |> get(path) |> response(200)

    test "an ordinary account is public and indexable, with text for search engines" do
      identity = register("seo_open") |> set_identity(bio: "<p>My bio</p>")
      public_post(identity)

      body = profile_meta(identity)

      assert body["public"] == true
      assert body["indexable"] == true
      assert body["seo"]["handle"] == identity.handle
      assert body["seo"]["bio"] == "My bio"
      assert [%{"text" => "Visible text"}] = body["seo"]["posts"]
    end

    test "search engine text is plain, with HTML entities decoded" do
      # The web app escapes this text again when rendering it, so an encoded
      # quote showed as a literal `&quot;` on the profile.
      identity = register("seo_entities")
      public_post(identity, %{"content" => ~s("respecter" & 'tom' <tag>)})

      assert [%{"text" => text}] = profile_meta(identity)["seo"]["posts"]
      refute text =~ "&quot;"
      refute text =~ "&amp;"
      assert text =~ ~s("respecter")
      assert text =~ "&"
    end

    test "only public top-level posts reach the search engine text" do
      identity = register("seo_posts")
      kept = public_post(identity)
      public_post(identity, %{"visibility" => "followers"})
      public_post(identity, %{"parent_id" => kept.id})
      hidden = public_post(identity)

      Repo.update_all(from(p in Hybridsocial.Social.Post, where: p.id == ^hidden.id),
        set: [hidden_at: DateTime.utc_now()]
      )

      assert [%{"id" => id}] = profile_meta(identity)["seo"]["posts"]
      assert id == kept.id
    end

    test "staff blocking indexing keeps the page public but out of search" do
      identity = register("seo_blocked") |> set_identity(search_indexing_blocked: true)
      post = public_post(identity)

      body = profile_meta(identity)
      assert body["public"] == true
      assert body["indexable"] == false
      assert body["seo"] == nil

      assert %{"public" => true, "indexable" => false, "seo" => nil} = post_meta(post)
    end

    test "each thing that should stop indexing does" do
      for fields <- [
            [discoverable: false],
            [allow_unfurl: false],
            [is_silenced: true]
          ] do
        identity = register("seo_opt") |> set_identity(fields)
        body = profile_meta(identity)

        assert body["public"] == true, "#{inspect(fields)} should stay viewable"
        assert body["indexable"] == false, "#{inspect(fields)} should not be indexable"
        assert body["seo"] == nil
      end
    end

    test "a locked account isn't public, and its link preview gives nothing away" do
      identity =
        register("seo_locked")
        |> set_identity(is_locked: true, display_name: "Real Name", bio: "Secret bio")

      post = public_post(identity, %{"content" => "marked public"})

      body = profile_meta(identity)
      assert %{"public" => false, "indexable" => false, "seo" => nil} = body
      refute inspect(body) =~ "Real Name"
      refute inspect(body) =~ "Secret bio"

      post_body = post_meta(post)
      assert %{"public" => false, "indexable" => false, "seo" => nil} = post_body
      refute inspect(post_body) =~ "marked public"
    end

    test "a shadow-banned account isn't public" do
      identity = register("seo_shadow") |> set_identity(is_shadow_banned: true)
      assert %{"public" => false, "indexable" => false} = profile_meta(identity)
    end

    test "a remote account isn't public" do
      identity = register("seo_remote") |> set_identity(is_local: false)
      assert %{"public" => false, "indexable" => false} = profile_meta(identity)
    end

    test "public_timeline_access none closes public pages" do
      identity = register("seo_closed")
      assert profile_meta(identity)["public"] == true

      :ok = Hybridsocial.Config.set("public_timeline_access", "none")
      assert %{"public" => false, "indexable" => false} = profile_meta(identity)
      assert PublicProfile.public?(identity) == false
    end

    test "a private post isn't public, and exposes nothing for search" do
      identity = register("seo_private")

      for visibility <- ["followers", "direct"] do
        post = public_post(identity, %{"content" => "secret", "visibility" => visibility})
        body = post_meta(post)

        assert %{"public" => false, "indexable" => false, "seo" => nil} = body
        refute inspect(body) =~ "secret"
      end
    end

    test "an unlisted post can be viewed but not indexed" do
      identity = register("seo_unlisted")
      post = public_post(identity, %{"visibility" => "unlisted"})

      assert %{"public" => true, "indexable" => false} = post_meta(post)
    end

    test "a public post is public and indexable with its text" do
      identity = register("seo_post")
      post = public_post(identity)

      assert %{"public" => true, "indexable" => true, "seo" => %{"text" => "Visible text"}} =
               post_meta(post)
    end

    test "sitemaps leave out everything that shouldn't be indexed" do
      open = register("map_open")
      open_post = public_post(open)

      excluded =
        for {name, fields} <- [
              {"map_blocked", [search_indexing_blocked: true]},
              {"map_undisc", [discoverable: false]},
              {"map_locked", [is_locked: true]},
              {"map_silenced", [is_silenced: true]},
              {"map_remote", [is_local: false]}
            ] do
          identity = register(name) |> set_identity(fields)
          {identity, public_post(identity)}
        end

      profiles = sitemap("/sitemap/profiles/1")
      posts = sitemap("/sitemap/posts/1")

      assert profiles =~ "/@#{open.handle}"
      assert posts =~ open_post.id

      for {identity, post} <- excluded do
        refute profiles =~ "/@#{identity.handle}<"
        refute posts =~ post.id
      end
    end

    test "a user can't clear or set the staff block through their profile" do
      identity =
        create_user("seo_self#{System.unique_integer([:positive])}")
        |> set_identity(search_indexing_blocked: true)

      conn =
        build_conn()
        |> auth_conn(identity)
        |> patch("/api/v1/accounts/update_credentials", %{"search_indexing_blocked" => false})

      assert json_response(conn, 200)
      assert Repo.get!(Identity, identity.id).search_indexing_blocked == true
    end

    test "staff can block and unblock, and it's validated" do
      identity = register("seo_admin")
      admin_conn = build_conn() |> admin_conn(create_admin("seoadmin"))
      path = "/api/v1/admin/users/#{identity.id}/search_indexing"

      assert %{"search_indexing_blocked" => true} =
               admin_conn |> put(path, %{"blocked" => true}) |> json_response(200)

      assert Repo.get!(Identity, identity.id).search_indexing_blocked == true

      assert %{"search_indexing_blocked" => true} =
               admin_conn |> get("/api/v1/admin/users/#{identity.id}") |> json_response(200)

      assert admin_conn |> put(path, %{"blocked" => "yes"}) |> json_response(422)

      assert %{"search_indexing_blocked" => false} =
               admin_conn |> put(path, %{"blocked" => false}) |> json_response(200)
    end

    test "a regular user can't use the admin control" do
      identity = register("seo_target")

      conn =
        build_conn() |> auth_conn(create_user("seo_plain#{System.unique_integer([:positive])}"))

      response =
        put(conn, "/api/v1/admin/users/#{identity.id}/search_indexing", %{"blocked" => true})

      assert response.status in [401, 403]
      assert Repo.get!(Identity, identity.id).search_indexing_blocked == false
    end
  end
end
