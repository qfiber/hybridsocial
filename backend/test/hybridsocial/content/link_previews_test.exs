defmodule Hybridsocial.Content.LinkPreviewsTest do
  use Hybridsocial.DataCase, async: true

  import Ecto.Query

  alias Hybridsocial.Content.LinkPreviews

  describe "extract_urls/1" do
    test "extracts URLs from text" do
      text = "Check out https://example.com and http://test.org/page"
      urls = LinkPreviews.extract_urls(text)
      assert length(urls) == 2
      assert "https://example.com" in urls
      assert "http://test.org/page" in urls
    end

    test "returns empty list for text without URLs" do
      assert LinkPreviews.extract_urls("no urls here") == []
    end

    test "returns empty list for nil" do
      assert LinkPreviews.extract_urls(nil) == []
    end

    test "extracts URLs with paths and query strings" do
      text = "Visit https://example.com/path?q=1&b=2 for info"
      urls = LinkPreviews.extract_urls(text)
      assert length(urls) == 1
      assert hd(urls) == "https://example.com/path?q=1&b=2"
    end
  end

  describe "validate_url/1 - SSRF prevention" do
    test "rejects private IP addresses" do
      assert {:error, :private_ip} = LinkPreviews.validate_url("http://192.168.1.1/page")
      assert {:error, :private_ip} = LinkPreviews.validate_url("http://10.0.0.1/page")
      assert {:error, :private_ip} = LinkPreviews.validate_url("http://127.0.0.1/page")
      assert {:error, :private_ip} = LinkPreviews.validate_url("http://localhost/page")
    end

    test "rejects 172.16-31.x range" do
      assert {:error, :private_ip} = LinkPreviews.validate_url("http://172.16.0.1/page")
      assert {:error, :private_ip} = LinkPreviews.validate_url("http://172.31.255.255/page")
    end

    test "allows public IP addresses" do
      assert {:ok, _} = LinkPreviews.validate_url("http://8.8.8.8/page")
    end

    test "rejects URLs without host" do
      assert {:error, :invalid_url} = LinkPreviews.validate_url("not-a-url")
    end
  end

  describe "user_agent_for/1 - per-host UA selection" do
    test "uses default UA for arbitrary hosts" do
      assert LinkPreviews.user_agent_for("https://example.com/page") =~ "HybridSocial"
      assert LinkPreviews.user_agent_for("https://news.ycombinator.com/") =~ "HybridSocial"
    end

    test "spoofs facebookexternalhit for Facebook properties" do
      assert LinkPreviews.user_agent_for("https://www.facebook.com/share/p/abc/") =~
               "facebookexternalhit"

      assert LinkPreviews.user_agent_for("https://m.facebook.com/foo") =~ "facebookexternalhit"

      assert LinkPreviews.user_agent_for("https://www.instagram.com/p/xyz/") =~
               "facebookexternalhit"

      assert LinkPreviews.user_agent_for("https://www.threads.net/@user/post/123") =~
               "facebookexternalhit"
    end

    test "spoofs Twitterbot for X / Twitter" do
      assert LinkPreviews.user_agent_for("https://x.com/user/status/1") =~ "Twitterbot"
      assert LinkPreviews.user_agent_for("https://twitter.com/user/status/1") =~ "Twitterbot"
    end

    test "spoofs LinkedInBot for LinkedIn" do
      assert LinkPreviews.user_agent_for("https://www.linkedin.com/posts/abc") =~ "LinkedInBot"
    end

    test "host-suffix match doesn't false-positive on lookalike domains" do
      # "evil-facebook.com" must not match "facebook.com"
      assert LinkPreviews.user_agent_for("https://evil-facebook.com/") =~ "HybridSocial"
      assert LinkPreviews.user_agent_for("https://notinstagram.com/") =~ "HybridSocial"
    end

    test "handles URLs without a host" do
      assert LinkPreviews.user_agent_for("not-a-url") =~ "HybridSocial"
    end
  end

  describe "fetch_preview/1 - local host short-circuit" do
    alias Hybridsocial.Repo
    alias Hybridsocial.Social.Post

    defp own_url(path) do
      base = HybridsocialWeb.Endpoint.url()
      base <> path
    end

    defp create_post(identity, attrs \\ %{}) do
      defaults = %{
        identity_id: identity.id,
        content: "Hello from #{identity.handle}",
        visibility: "public",
        post_type: "text"
      }

      %Post{}
      |> Post.create_changeset(Map.merge(defaults, attrs))
      |> Repo.insert!()
    end

    test "builds a preview from DB for own /post/:id without HTTP fetch" do
      user = create_user("local_preview_a")
      post = create_post(user, %{content: "hello world body text"})

      assert {:ok, meta} = LinkPreviews.fetch_preview(own_url("/post/#{post.id}"))
      assert is_binary(meta.title)
      assert meta.title =~ user.handle
      assert meta.description =~ "hello world"
      assert meta.site_name
    end

    test "returns generic preview for nonexistent local post" do
      bogus = "00000000-0000-0000-0000-000000000000"
      assert {:ok, meta} = LinkPreviews.fetch_preview(own_url("/post/#{bogus}"))
      assert is_binary(meta.title)
    end

    test "builds a preview from DB for own /@:handle when allow_unfurl" do
      user = create_user("local_preview_b")

      # allow_unfurl defaults vary; force-set so the test is hermetic.
      Repo.update_all(
        from(i in Hybridsocial.Accounts.Identity, where: i.id == ^user.id),
        set: [allow_unfurl: true]
      )

      assert {:ok, meta} = LinkPreviews.fetch_preview(own_url("/@#{user.handle}"))
      assert meta.title =~ user.handle
      assert meta.site_name
    end
  end

  describe "cached_preview_for_post/1 - never fetches inline" do
    alias Hybridsocial.Content.LinkPreview

    defp hash(url), do: :crypto.hash(:sha256, url) |> Base.encode16(case: :lower)

    defp insert_preview(url, attrs) do
      Hybridsocial.Repo.insert!(
        struct(
          LinkPreview,
          Map.merge(
            %{url_hash: hash(url), url: url, fetched_at: DateTime.utc_now(), ttl: 86_400},
            attrs
          )
        )
      )
    end

    test "an uncached remote link returns no card without fetching" do
      post = %{content: "read https://example.com/uncached-article"}
      assert {:error, :pending} = LinkPreviews.cached_preview_for_post(post)

      assert Hybridsocial.Repo.get(LinkPreview, hash("https://example.com/uncached-article")) ==
               nil
    end

    test "a cached preview is returned, even when expired" do
      url = "https://example.com/cached-article"
      insert_preview(url, %{title: "Cached", fetched_at: ~U[2020-01-01 00:00:00.000000Z]})

      assert {:ok, %LinkPreview{title: "Cached"}} =
               LinkPreviews.cached_preview_for_post(%{content: url})
    end

    test "a cached failure gives no card" do
      url = "https://example.com/failed-article"
      insert_preview(url, %{ttl: 21_600})

      assert {:error, :no_preview} = LinkPreviews.cached_preview_for_post(%{content: url})
    end

    test "a failed fetch is cached so it isn't retried on every view" do
      url = "http://10.0.0.1/private"
      assert {:error, _} = LinkPreviews.get_or_fetch(url)

      assert %LinkPreview{title: nil, ttl: 21_600} =
               Hybridsocial.Repo.get(LinkPreview, hash(url))

      assert {:error, :no_preview} = LinkPreviews.get_or_fetch(url)
    end
  end
end
