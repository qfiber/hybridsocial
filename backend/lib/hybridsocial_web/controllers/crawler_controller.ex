defmodule HybridsocialWeb.CrawlerController do
  @moduledoc """
  Server-rendered OG/Twitter Card shells for social crawlers.

  Crawlers (FacebookExternalHit, TelegramBot, WhatsApp, Twitterbot, etc.)
  don't run JavaScript. When a user shares a `/post/:id` or `/@handle` URL
  in chat or on another social platform, the platform fetches the URL as
  one of these bots and looks for OG meta tags. The SPA can't serve those.

  Routes only actually render OG content if the request's User-Agent looks
  like a known crawler. Other requests — real browsers — get a tiny
  redirect shell that hands off to the SPA. In production Caddy can
  route crawler UAs here directly and leave browser requests on the
  static SPA bundle.

  Visibility rules for posts:

    - Public + local  → full OG (title, description, image, type=article)
    - Followers, group, direct, list → placeholder ("Private post on
      <instance name>"). We don't leak content or images.
    - Deleted         → placeholder.
    - Non-existent    → 404.

  For profiles: respects `identity.allow_unfurl`. When false, the
  crawler sees the placeholder "User on <instance name>" with no
  display_name, bio, avatar.

  The instance name is read from the `instance_name` config key, not
  hardcoded.
  """
  use HybridsocialWeb, :controller

  import Ecto.Query

  alias Hybridsocial.Accounts
  alias Hybridsocial.Accounts.PublicProfile
  alias Hybridsocial.Config
  alias Hybridsocial.Content.LinkPreviews
  alias Hybridsocial.Media.MediaFile
  alias Hybridsocial.Repo
  alias Hybridsocial.Social.Post
  alias Hybridsocial.SitePages
  alias HybridsocialWeb.Helpers.UserAgent

  # Fallback OG image. The operator can override with the `instance_og_image`
  # config key; otherwise we use the site's default brand icon.
  @placeholder_image_path "/icons/icon.svg"

  # How many recent posts a profile's initial HTML carries for search engines.
  @seo_recent_posts 20

  # ---------------------------------------------------------------------------
  # GET /post/:id
  # ---------------------------------------------------------------------------

  def post(conn, %{"id" => id}) do
    if UserAgent.crawler?(conn) do
      case fetch_post(id) do
        {:ok, :public, post} -> render_og(conn, post_og_public(post))
        {:ok, :private, post} -> render_og(conn, post_og_private(post))
        {:error, :not_found} -> send_resp(conn, 404, "Not found")
      end
    else
      send_spa_handoff(conn)
    end
  end

  # JSON variant of `post/2` for the frontend SSR. Same privacy rules:
  # only strictly-public local posts return content, everything else
  # returns the neutral private placeholder.
  def post_meta(conn, %{"id" => id}) do
    case fetch_post(id) do
      {:ok, :public, post} -> json(conn, post_og_public(post) |> Map.merge(post_access(post)))
      {:ok, :private, post} -> json(conn, post_og_private(post) |> Map.merge(post_access(post)))
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "not_found"})
    end
  end

  # ---------------------------------------------------------------------------
  # GET /@:handle
  # ---------------------------------------------------------------------------

  def profile(conn, %{"handle" => handle}) do
    if UserAgent.crawler?(conn) do
      case Accounts.get_identity_by_handle(handle) do
        %{allow_unfurl: true, is_locked: false, deleted_at: nil, is_suspended: false} = identity ->
          render_og(conn, profile_og_full(identity))

        %{deleted_at: nil, is_suspended: false} = identity ->
          render_og(conn, profile_og_placeholder(identity))

        _ ->
          send_resp(conn, 404, "Not found")
      end
    else
      send_spa_handoff(conn)
    end
  end

  # JSON variant of `profile/2` for the frontend SSR. Only unfurl-allowed,
  # live profiles expose bio/avatar; others get a neutral placeholder so a
  # private/locked profile never leaks content.
  def profile_meta(conn, %{"handle" => handle}) do
    case Accounts.get_identity_by_handle(handle) do
      # A link preview of a locked account shows nothing but the placeholder, or it
      # would give away the name and bio that the page itself no longer shows.
      %{allow_unfurl: true, is_locked: false, deleted_at: nil, is_suspended: false} = identity ->
        json(conn, profile_og_full(identity) |> Map.merge(profile_access(identity)))

      %{deleted_at: nil, is_suspended: false} = identity ->
        json(conn, profile_og_placeholder(identity) |> Map.merge(profile_access(identity)))

      _ ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})
    end
  end

  # ---------------------------------------------------------------------------
  # GET /legal/:slug
  # ---------------------------------------------------------------------------

  @doc "GET / — server-rendered OG shell for the instance home page."
  def home(conn, _params) do
    if UserAgent.crawler?(conn) do
      render_og(conn, home_og())
    else
      send_spa_handoff(conn)
    end
  end

  def legal(conn, %{"slug" => slug}) do
    if UserAgent.crawler?(conn) do
      case SitePages.get_published_page(slug) do
        %{title: title, body_markdown: markdown} ->
          render_og(conn, legal_og(slug, title, markdown))

        _ ->
          send_resp(conn, 404, "Not found")
      end
    else
      send_spa_handoff(conn)
    end
  end

  # ---------------------------------------------------------------------------
  # Sitemaps — index + paginated child sitemaps
  #
  # The protocol allows 50,000 URLs and 50MB per sitemap. We cap at 5,000 per
  # child — comfortably under the limits, and an instance with millions of
  # posts still only needs ~1000 child sitemaps.
  # ---------------------------------------------------------------------------

  @sitemap_per_page 5000

  @doc "GET /sitemap.xml — sitemap index pointing at child sitemaps."
  def sitemap(conn, _params) do
    base = base_url()

    child_entries =
      [sitemap_index_entry(base, "/sitemap/static")] ++
        post_page_entries(base) ++
        profile_page_entries(base)

    body =
      [
        ~s(<?xml version="1.0" encoding="UTF-8"?>\n),
        ~s(<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n),
        child_entries,
        "</sitemapindex>\n"
      ]
      |> IO.iodata_to_binary()

    send_xml(conn, body)
  end

  @doc "GET /sitemap/static — home, directory, legal pages."
  def sitemap_static(conn, _params) do
    base = base_url()

    urls = [
      sitemap_url(base, "/", priority: "1.0", changefreq: "daily"),
      sitemap_url(base, "/directory", priority: "0.8", changefreq: "daily"),
      sitemap_url(base, "/legal/about", priority: "0.6", changefreq: "monthly"),
      sitemap_url(base, "/legal/privacy", priority: "0.4", changefreq: "yearly"),
      sitemap_url(base, "/legal/terms", priority: "0.4", changefreq: "yearly")
    ]

    send_xml(conn, urlset(urls))
  end

  @doc "GET /sitemap/posts/:page — paginated public posts."
  def sitemap_posts(conn, %{"page" => page_param}) do
    page = parse_page(page_param)
    base = base_url()
    offset_n = (page - 1) * @sitemap_per_page

    urls =
      public_posts_query()
      |> order_by([p], desc: p.inserted_at)
      |> offset(^offset_n)
      |> limit(^@sitemap_per_page)
      |> select([p], {p.id, p.updated_at})
      |> Repo.all()
      |> Enum.map(fn {id, updated_at} ->
        sitemap_url(base, "/post/#{id}",
          lastmod: iso8601(updated_at),
          priority: "0.7",
          changefreq: "weekly"
        )
      end)

    send_xml(conn, urlset(urls))
  end

  @doc "GET /sitemap/profiles/:page — paginated discoverable profiles."
  def sitemap_profiles(conn, %{"page" => page_param}) do
    page = parse_page(page_param)
    base = base_url()
    offset_n = (page - 1) * @sitemap_per_page

    urls =
      discoverable_profiles_query()
      |> order_by([i], desc: i.inserted_at)
      |> offset(^offset_n)
      |> limit(^@sitemap_per_page)
      |> select([i], {i.handle, i.updated_at})
      |> Repo.all()
      |> Enum.map(fn {handle, updated_at} ->
        sitemap_url(base, "/@#{handle}",
          lastmod: iso8601(updated_at),
          priority: "0.6",
          changefreq: "weekly"
        )
      end)

    send_xml(conn, urlset(urls))
  end

  # --- Public view and search indexing ---

  # What the web app needs to serve a page to a logged-out visitor. `seo` is text
  # rendered in the page's initial HTML, so it's only sent for what may be indexed.
  defp profile_access(identity) do
    indexable = PublicProfile.indexable?(identity)

    %{
      public: PublicProfile.public?(identity),
      indexable: indexable,
      seo: if(indexable, do: profile_seo(identity))
    }
  end

  defp profile_seo(identity) do
    %{
      name: identity.display_name || identity.handle,
      handle: identity.handle,
      bio: text_only(identity.bio),
      posts: Enum.map(recent_public_posts(identity.id), &post_seo/1)
    }
  end

  defp recent_public_posts(identity_id) do
    from(p in Post,
      where:
        p.identity_id == ^identity_id and p.visibility == "public" and is_nil(p.deleted_at) and
          is_nil(p.hidden_at) and not is_nil(p.published_at) and is_nil(p.parent_id),
      order_by: [desc: p.published_at, desc: p.id],
      limit: @seo_recent_posts
    )
    |> Repo.all()
  end

  defp post_seo(post) do
    %{
      id: post.id,
      text: text_only(post.content_html || post.content),
      published_at: post.published_at
    }
  end

  defp post_access(post) do
    author = Repo.preload(post, :identity).identity
    live = is_nil(post.deleted_at) and is_nil(post.hidden_at) and not is_nil(post.published_at)
    public = live and post.visibility in ["public", "unlisted"] and PublicProfile.public?(author)
    indexable = public and post.visibility == "public" and PublicProfile.indexable?(author)

    %{
      public: public,
      indexable: indexable,
      seo:
        if(indexable,
          do:
            post_seo(post)
            |> Map.merge(%{name: author.display_name || author.handle, handle: author.handle})
        )
    }
  end

  # ---------------------------------------------------------------------------
  # Sitemap helpers
  # ---------------------------------------------------------------------------

  defp public_posts_query do
    # Local posts only, keyed off the author's is_local flag. We can NOT
    # use is_nil(ap_id): every local post is stamped with a self-hosted
    # ap_id at creation, so that check excluded the whole local corpus and
    # left the sitemap permanently empty. Also drop unpublished
    # (scheduled/draft) and admin-hidden posts — they're not crawlable.
    Post
    |> join(:inner, [p], i in Hybridsocial.Accounts.Identity, on: i.id == p.identity_id)
    |> where([p], p.visibility == "public")
    |> where([p], is_nil(p.deleted_at))
    |> where([p], is_nil(p.hidden_at))
    |> where([p], not is_nil(p.published_at))
    |> where([_p, i], i.is_local == true)
    |> where_author_indexable()
  end

  # The sitemap has to agree with PublicProfile.indexable?/1, or it advertises
  # pages that then say noindex.
  defp where_author_indexable(query) do
    where(
      query,
      [_p, i],
      is_nil(i.deleted_at) and i.is_suspended == false and i.is_shadow_banned == false and
        i.discoverable == true and i.allow_unfurl == true and i.is_locked == false and
        i.is_silenced == false and i.search_indexing_blocked == false
    )
  end

  defp discoverable_profiles_query do
    Hybridsocial.Accounts.Identity
    |> where([i], i.type == "user")
    |> where([i], is_nil(i.deleted_at))
    |> where([i], i.is_suspended == false)
    |> where([i], i.is_shadow_banned == false)
    |> where([i], i.allow_unfurl == true)
    |> where([i], is_nil(i.parent_identity_id))
    |> where([i], i.is_local == true)
    |> where([i], i.discoverable == true)
    |> where([i], i.is_locked == false)
    |> where([i], i.is_silenced == false)
    |> where([i], i.search_indexing_blocked == false)
  end

  defp post_page_entries(base) do
    count = Repo.aggregate(public_posts_query(), :count)
    pages = ceil_div(count, @sitemap_per_page)

    for page <- 1..pages//1 do
      sitemap_index_entry(base, "/sitemap/posts/#{page}")
    end
  end

  defp profile_page_entries(base) do
    count = Repo.aggregate(discoverable_profiles_query(), :count)
    pages = ceil_div(count, @sitemap_per_page)

    for page <- 1..pages//1 do
      sitemap_index_entry(base, "/sitemap/profiles/#{page}")
    end
  end

  defp ceil_div(0, _), do: 0
  defp ceil_div(n, d), do: div(n + d - 1, d)

  defp urlset(urls) do
    [
      ~s(<?xml version="1.0" encoding="UTF-8"?>\n),
      ~s(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n),
      urls,
      "</urlset>\n"
    ]
    |> IO.iodata_to_binary()
  end

  defp send_xml(conn, body) do
    conn
    |> put_resp_content_type("application/xml; charset=utf-8")
    |> send_resp(200, body)
  end

  defp sitemap_index_entry(base, path) do
    [
      "  <sitemap>\n",
      "    <loc>#{escape_html(base <> path)}</loc>\n",
      "  </sitemap>\n"
    ]
  end

  defp sitemap_url(base, path, opts) do
    loc = escape_html(base <> path)
    lastmod = Keyword.get(opts, :lastmod)
    priority = Keyword.get(opts, :priority)
    changefreq = Keyword.get(opts, :changefreq)

    [
      "  <url>\n",
      "    <loc>#{loc}</loc>\n",
      if(lastmod, do: "    <lastmod>#{lastmod}</lastmod>\n", else: ""),
      if(changefreq, do: "    <changefreq>#{changefreq}</changefreq>\n", else: ""),
      if(priority, do: "    <priority>#{priority}</priority>\n", else: ""),
      "  </url>\n"
    ]
  end

  defp parse_page(val) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} when n > 0 -> n
      _ -> 1
    end
  end

  defp parse_page(_), do: 1

  defp iso8601(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp iso8601(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp iso8601(_), do: nil

  # ---------------------------------------------------------------------------
  # GET /robots.txt
  # ---------------------------------------------------------------------------

  def robots(conn, _params) do
    body = """
    User-agent: *
    Allow: /post/
    Allow: /@
    Allow: /legal/
    Allow: /tags/
    Allow: /directory
    Disallow: /messages
    Disallow: /notifications
    Disallow: /settings
    Disallow: /admin
    Disallow: /api/
    Disallow: /drafts
    Disallow: /bookmarks
    Disallow: /favourites
    Disallow: /scheduled

    Sitemap: #{base_url()}/sitemap.xml
    """

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, body)
  end

  # ---------------------------------------------------------------------------
  # OG builders — return a map of {title, description, image, type, url}
  # ---------------------------------------------------------------------------

  defp home_og do
    instance = instance_name()

    description =
      Config.get("instance_short_description", Config.get("instance_description", ""))
      |> default_if_blank("#{instance} — a decentralized social network")

    %{
      title: instance,
      description: description,
      image: default_instance_image(),
      type: "website",
      url: base_url() <> "/",
      site_name: instance,
      author: nil
    }
  end

  defp post_og_public(post) do
    post = Repo.preload(post, [:identity, :media_attachments])
    instance = instance_name()
    author_name = post.identity.display_name || post.identity.handle
    title = "#{author_name} on #{instance}"

    description =
      post.content
      |> text_only()
      |> truncate(300)
      |> default_if_blank("A post on #{instance}")

    img = post_image_meta(post)

    %{
      title: title,
      description: description,
      image: img.url,
      image_width: img.width,
      image_height: img.height,
      type: "article",
      url: "#{base_url()}/post/#{post.id}",
      site_name: instance,
      author: author_name
    }
  end

  defp post_og_private(post) do
    instance = instance_name()

    %{
      title: "Private post on #{instance}",
      description:
        "This post is only visible to the people its author shared it with. Sign in to view.",
      image: default_instance_image(),
      type: "website",
      url: "#{base_url()}/post/#{post.id}",
      site_name: instance,
      author: nil
    }
  end

  defp profile_og_full(identity) do
    instance = instance_name()
    name = identity.display_name || identity.handle
    title = "#{name} (@#{identity.handle}) on #{instance}"

    description =
      identity.bio
      |> text_only()
      |> truncate(300)
      |> default_if_blank("Profile on #{instance}")

    %{
      title: title,
      description: description,
      image: identity.avatar_url || default_instance_image(),
      type: "profile",
      url: "#{base_url()}/@#{identity.handle}",
      site_name: instance,
      author: name
    }
  end

  defp profile_og_placeholder(identity) do
    instance = instance_name()

    %{
      title: "User on #{instance}",
      description: "A member of #{instance}.",
      image: default_instance_image(),
      type: "profile",
      url: "#{base_url()}/@#{identity.handle}",
      site_name: instance,
      author: nil
    }
  end

  defp legal_og(slug, title, markdown) do
    instance = instance_name()

    description =
      markdown
      |> text_only()
      |> truncate(300)
      |> default_if_blank("#{title} for #{instance}")

    %{
      title: "#{title} — #{instance}",
      description: description,
      image: default_instance_image(),
      type: "article",
      url: "#{base_url()}/legal/#{slug}",
      site_name: instance,
      author: nil
    }
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  # sobelow_skip ["XSS.SendResp"]
  defp render_og(conn, og) do
    # Safe: html is built entirely from server-side og data where every
    # interpolated field goes through `escape_html/1` in build_html/1
    # before landing in the template string.
    html = build_html(og)

    conn
    |> put_resp_content_type("text/html; charset=utf-8")
    |> send_resp(200, html)
  end

  defp build_html(og) do
    esc = &escape_html/1

    """
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>#{esc.(og.title)}</title>
    <meta name="description" content="#{esc.(og.description)}" />
    <link rel="canonical" href="#{esc.(og.url)}" />
    <meta property="og:title" content="#{esc.(og.title)}" />
    <meta property="og:description" content="#{esc.(og.description)}" />
    <meta property="og:image" content="#{esc.(og.image)}" />
    <meta property="og:type" content="#{esc.(og.type)}" />
    <meta property="og:url" content="#{esc.(og.url)}" />
    <meta property="og:site_name" content="#{esc.(og.site_name)}" />
    <meta name="twitter:card" content="summary_large_image" />
    <meta name="twitter:title" content="#{esc.(og.title)}" />
    <meta name="twitter:description" content="#{esc.(og.description)}" />
    <meta name="twitter:image" content="#{esc.(og.image)}" />
    <meta http-equiv="refresh" content="0; url=#{esc.(og.url)}" />
    </head>
    <body>
    <p>Redirecting to <a href="#{esc.(og.url)}">#{esc.(og.url)}</a>…</p>
    </body>
    </html>
    """
  end

  # Browsers hitting these Phoenix routes are an edge case — normally Caddy
  # routes browser requests directly to the SPA bundle. If they land here,
  # emit a minimal redirect shell so they still get to the SPA.
  # sobelow_skip ["XSS.SendResp"]
  defp send_spa_handoff(conn) do
    # Safe: the only interpolations are `instance_name/0` (config
    # string, escape_html'd) and the request URL (escape_html'd + JSON
    # -encoded for the JS redirect). No user input reaches the HTML.
    url = build_request_url(conn)

    html = """
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8" />
    <title>#{escape_html(instance_name())}</title>
    <meta http-equiv="refresh" content="0; url=#{escape_html(url)}" />
    <script>window.location.replace(#{Jason.encode!(url)});</script>
    </head>
    <body></body>
    </html>
    """

    conn
    |> put_resp_content_type("text/html; charset=utf-8")
    |> send_resp(200, html)
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp fetch_post(id) do
    case Repo.get(Post, id) do
      nil ->
        {:error, :not_found}

      %Post{deleted_at: deleted_at} = post when not is_nil(deleted_at) ->
        {:ok, :private, post}

      %Post{visibility: "public", ap_id: ap_id} = post ->
        if local_or_unknown_ap_id?(ap_id) and
             not Repo.preload(post, :identity).identity.is_locked,
           do: {:ok, :public, post},
           else: {:ok, :private, post}

      %Post{} = post ->
        {:ok, :private, post}
    end
  end

  defp local_or_unknown_ap_id?(nil), do: true

  defp local_or_unknown_ap_id?(ap_id) when is_binary(ap_id) do
    base = base_url()
    String.starts_with?(ap_id, base)
  end

  # Returns the OG image url + its real pixel dimensions (nil when the
  # image is a fallback we don't have dimensions for, so callers omit the
  # width/height tags rather than assume a size).
  defp post_image_meta(%Post{} = post) do
    attachments =
      case post.media_attachments do
        %Ecto.Association.NotLoaded{} ->
          Repo.all(
            from(m in MediaFile,
              where: m.post_id == ^post.id and is_nil(m.deleted_at),
              order_by: [asc: m.inserted_at],
              limit: 1
            )
          )

        list when is_list(list) ->
          Enum.filter(list, &(is_nil(&1.deleted_at) and image_like?(&1)))
      end

    case attachments do
      [%MediaFile{} = media | _] ->
        %{url: Hybridsocial.Media.media_url(media), width: media.width, height: media.height}

      _ ->
        %{url: post_card_image(post) || default_instance_image(), width: nil, height: nil}
    end
  end

  defp image_like?(%MediaFile{content_type: "image/" <> _}), do: true
  defp image_like?(_), do: false

  # Fall back to the post's link preview card image if no attachment fits.
  defp post_card_image(%Post{} = post) do
    case LinkPreviews.preview_for_post(post) do
      {:ok, %{image: image}} when is_binary(image) and image != "" -> image
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp default_instance_image do
    case Config.get("instance_og_image") do
      url when is_binary(url) and url != "" -> absolute(url)
      _ -> absolute(@placeholder_image_path)
    end
  end

  defp absolute("http" <> _ = url), do: url
  defp absolute("/" <> _ = path), do: base_url() <> path
  defp absolute(path) when is_binary(path), do: base_url() <> "/" <> path
  defp absolute(_), do: base_url() <> @placeholder_image_path

  defp instance_name do
    Config.get("instance_name", "HybridSocial")
  end

  defp base_url do
    HybridsocialWeb.Endpoint.url()
  end

  defp build_request_url(%Plug.Conn{} = conn) do
    base_url() <> conn.request_path <> build_query_string(conn)
  end

  defp build_query_string(%Plug.Conn{query_string: ""}), do: ""
  defp build_query_string(%Plug.Conn{query_string: qs}) when is_binary(qs), do: "?" <> qs

  defp text_only(nil), do: ""

  defp text_only(html_or_text) when is_binary(html_or_text) do
    html_or_text
    |> String.replace(~r/<[^>]+>/u, " ")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp truncate(text, max) when is_binary(text) do
    if String.length(text) <= max do
      text
    else
      text
      |> String.slice(0, max - 1)
      |> String.trim_trailing()
      |> Kernel.<>("…")
    end
  end

  defp default_if_blank("", fallback), do: fallback
  defp default_if_blank(text, _fallback) when is_binary(text), do: text
  defp default_if_blank(_, fallback), do: fallback

  defp escape_html(nil), do: ""

  defp escape_html(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  defp escape_html(other), do: other |> to_string() |> escape_html()
end
