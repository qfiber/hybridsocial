defmodule Hybridsocial.Content.LinkPreviews do
  @moduledoc """
  Context module for link preview fetching and caching.
  """
  alias Hybridsocial.Repo
  alias Hybridsocial.Content.LinkPreview
  alias Hybridsocial.Social.Post
  alias Hybridsocial.Accounts
  alias Hybridsocial.SitePages
  alias Hybridsocial.Config
  alias Hybridsocial.Media.MediaFile

  @fetch_timeout 5_000
  @max_response_size 1_048_576

  # Crawler UAs we identify as for hosts that gate OG metadata behind a JS
  # login wall for generic bots but serve real tags to their own crawler.
  @meta_crawler_ua "facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)"
  @twitter_crawler_ua "Twitterbot/1.0"
  @linkedin_crawler_ua "LinkedInBot/1.0 (compatible; Mozilla/5.0; +http://www.linkedin.com)"

  # Match is host-suffix based: "m.facebook.com" matches "facebook.com".
  @spoofed_user_agents %{
    "facebook.com" => @meta_crawler_ua,
    "fb.com" => @meta_crawler_ua,
    "instagram.com" => @meta_crawler_ua,
    "threads.net" => @meta_crawler_ua,
    "twitter.com" => @twitter_crawler_ua,
    "x.com" => @twitter_crawler_ua,
    "t.co" => @twitter_crawler_ua,
    "linkedin.com" => @linkedin_crawler_ua
  }

  @doc """
  Checks cache for a preview by URL hash. Fetches if missing or expired.
  """
  def get_or_fetch(url) do
    url_hash = hash_url(url)

    case Repo.get(LinkPreview, url_hash) do
      nil ->
        fetch_and_store(url, url_hash)

      preview ->
        if expired?(preview) do
          fetch_and_store(url, url_hash)
        else
          {:ok, preview}
        end
    end
  end

  @doc """
  Fetches a URL and parses OpenGraph/meta tags from the HTML.

  Security measures:
  - Rejects private IP ranges (SSRF prevention)
  - 5 second timeout
  - 1MB max response size
  - No JavaScript execution
  - Custom User-Agent
  """
  def fetch_preview(url) do
    case classify_local_url(url) do
      {:local, kind, key} ->
        # Short-circuit own-host URLs to a DB lookup. Going over HTTP
        # lands at the SvelteKit SPA shell which has no server-rendered
        # OG tags, so the cached preview ends up with empty title /
        # description / image and no card renders. Building the
        # preview straight from the source row mirrors what the
        # CrawlerController serves to other instances' bots.
        local_preview(kind, key)

      :remote ->
        fetch_remote(url)
    end
  end

  defp fetch_remote(url) do
    if youtube_url?(url) do
      case fetch_youtube_oembed(url) do
        {:ok, meta} -> {:ok, meta}
        # oEmbed can fail when YouTube hides a video (region-blocked,
        # private, age-gated). Fall through to the normal HTML
        # parse so we still get *something* in the card.
        {:error, _} -> fetch_remote_html(url)
      end
    else
      fetch_remote_html(url)
    end
  end

  defp fetch_remote_html(url) do
    with {:ok, _url} <- validate_url(url) do
      headers = [{"User-Agent", user_agent_for(url)}]

      # follow_redirect: Facebook share/p/* URLs 302 to the canonical post URL,
      # so without this we error out with {:http_error, 302} and never see the
      # OG tags. max_redirect caps the chain so a redirect loop can't burn our
      # 5-second timeout budget.
      options = [
        recv_timeout: @fetch_timeout,
        timeout: @fetch_timeout,
        max_body_length: @max_response_size,
        follow_redirect: true,
        max_redirect: 3
      ]

      case Hybridsocial.HTTP.get(url, headers, options) do
        {:ok, %Hybridsocial.HTTP.Response{status_code: status, body: body}}
        when status >= 200 and status < 300 ->
          {:ok, parse_meta_tags(body)}

        {:ok, %Hybridsocial.HTTP.Response{status_code: status}} ->
          {:error, {:http_error, status}}

        {:error, %Hybridsocial.HTTP.Error{reason: reason}} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Validates a URL is not targeting a private IP address.
  Returns {:ok, url} or {:error, :private_ip}.
  """
  def validate_url(url) do
    uri = URI.parse(url)
    host = uri.host

    cond do
      is_nil(host) ->
        {:error, :invalid_url}

      host == "localhost" ->
        {:error, :private_ip}

      true ->
        case resolve_host(host) do
          {:ok, ip} ->
            if private_ip?(ip) do
              {:error, :private_ip}
            else
              {:ok, url}
            end

          {:error, _} ->
            # If we can't resolve, check if it's a direct IP
            case parse_ip(host) do
              {:ok, ip} ->
                if private_ip?(ip) do
                  {:error, :private_ip}
                else
                  {:ok, url}
                end

              :error ->
                {:ok, url}
            end
        end
    end
  end

  # YouTube serves an SPA shell to non-Googlebot user agents — the
  # <title> ends up as a bare " - YouTube" because the real value is
  # injected by client-side JS we never run. Use the public oEmbed
  # endpoint instead: works without auth, returns clean JSON, and
  # gives us the playlist title on /playlist links and the video
  # title on /watch links. Matches youtu.be, youtube.com, m.youtube,
  # music.youtube, and the regional youtube.<cctld> shortcuts.
  defp youtube_url?(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) ->
        host
        |> String.downcase()
        |> String.replace_prefix("www.", "")
        |> case do
          "youtu.be" -> true
          "youtube.com" -> true
          "m.youtube.com" -> true
          "music.youtube.com" -> true
          _ -> false
        end

      _ ->
        false
    end
  end

  defp fetch_youtube_oembed(url) do
    oembed_url =
      "https://www.youtube.com/oembed?format=json&url=" <> URI.encode_www_form(url)

    headers = [{"User-Agent", default_user_agent()}, {"Accept", "application/json"}]

    options = [
      recv_timeout: @fetch_timeout,
      timeout: @fetch_timeout,
      follow_redirect: true,
      max_redirect: 2
    ]

    case Hybridsocial.HTTP.get(oembed_url, headers, options) do
      {:ok, %Hybridsocial.HTTP.Response{status_code: status, body: body}}
      when status >= 200 and status < 300 ->
        case Jason.decode(body) do
          {:ok, json} ->
            {:ok,
             %{
               title: decode_entities(Map.get(json, "title")),
               # YouTube oEmbed doesn't ship a description. The author
               # name is the most useful thing to surface in the card
               # subtitle ("by Channel Name") so the card isn't blank.
               description: build_youtube_description(json),
               image: Map.get(json, "thumbnail_url"),
               site_name: "YouTube"
             }}

          {:error, _} ->
            {:error, :invalid_oembed_response}
        end

      {:ok, %Hybridsocial.HTTP.Response{status_code: status}} ->
        # 401/403 = embedding disabled; 404 = video taken down / private.
        # Either way, oEmbed isn't going to help — let the caller fall
        # back to the HTML path.
        {:error, {:http_error, status}}

      {:error, %Hybridsocial.HTTP.Error{reason: reason}} ->
        {:error, reason}
    end
  end

  defp build_youtube_description(%{"author_name" => name}) when is_binary(name) and name != "",
    do: "by " <> name

  defp build_youtube_description(_), do: nil

  @doc """
  Extracts URLs from text content using regex.
  """
  def extract_urls(text) when is_binary(text) do
    ~r/https?:\/\/[^\s<>"{}|\\^`\[\]]+/
    |> Regex.scan(text)
    |> List.flatten()
  end

  def extract_urls(_), do: []

  @doc """
  Picks the User-Agent header to send when fetching `url`. Most hosts get the
  default, but a handful of walled-garden platforms (Facebook, X, LinkedIn …)
  return empty OG tags to generic bots and only serve real metadata to their
  own crawler UA — so we identify as that crawler for those hosts.
  """
  def user_agent_for(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) ->
        normalized = String.replace_prefix(String.downcase(host), "www.", "")

        Enum.find_value(@spoofed_user_agents, default_user_agent(), fn {suffix, ua} ->
          if normalized == suffix or String.ends_with?(normalized, "." <> suffix), do: ua
        end)

      _ ->
        default_user_agent()
    end
  end

  @doc """
  Extracts the first URL from a post's content and fetches its preview.
  """
  def preview_for_post(post) do
    case extract_urls(post.content || "") do
      [first_url | _] -> get_or_fetch(first_url)
      [] -> {:error, :no_urls}
    end
  end

  # --- Local-host short-circuit ---

  # Returns {:local, :post, id} | {:local, :profile, handle} |
  # {:local, :legal, slug} | {:local, :generic, nil} for own-host URLs;
  # :remote otherwise. Generic catches an instance homepage / unknown
  # paths so a cookie banner / index URL still gets a sensible card
  # instead of an HTTP fetch that returns the SPA shell.
  defp classify_local_url(url) do
    uri = URI.parse(url)
    host = uri.host && String.downcase(uri.host)
    own = own_host()

    if is_binary(host) and is_binary(own) and host == own do
      classify_local_path(uri.path || "/")
    else
      :remote
    end
  end

  defp classify_local_path(path) do
    case path do
      "/post/" <> rest -> {:local, :post, String.split(rest, "/") |> List.first()}
      "/posts/" <> rest -> {:local, :post, String.split(rest, "/") |> List.first()}
      "/@" <> rest -> {:local, :profile, String.split(rest, "/") |> List.first()}
      "/legal/" <> rest -> {:local, :legal, String.split(rest, "/") |> List.first()}
      _ -> {:local, :generic, nil}
    end
  end

  defp own_host do
    case URI.parse(HybridsocialWeb.Endpoint.url()) do
      %URI{host: host} when is_binary(host) -> String.downcase(host)
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp local_preview(:post, id) when is_binary(id) and id != "" do
    case Repo.get(Post, id) do
      %Post{deleted_at: nil, visibility: "public"} = post ->
        post = Repo.preload(post, [:identity, :media_attachments])
        {:ok, post_meta(post)}

      _ ->
        {:ok, generic_meta()}
    end
  rescue
    _ -> {:ok, generic_meta()}
  end

  defp local_preview(:profile, handle) when is_binary(handle) and handle != "" do
    case Accounts.get_identity_by_handle(handle) do
      %{allow_unfurl: true, deleted_at: nil, is_suspended: false} = identity ->
        {:ok, profile_meta(identity)}

      _ ->
        {:ok, generic_meta()}
    end
  rescue
    _ -> {:ok, generic_meta()}
  end

  defp local_preview(:legal, slug) when is_binary(slug) and slug != "" do
    case SitePages.get_published_page(slug) do
      %{title: title, body_markdown: markdown} ->
        {:ok, legal_meta(title, markdown)}

      _ ->
        {:ok, generic_meta()}
    end
  rescue
    _ -> {:ok, generic_meta()}
  end

  defp local_preview(_, _), do: {:ok, generic_meta()}

  defp post_meta(%Post{} = post) do
    instance = instance_name()
    author = post.identity.display_name || post.identity.handle

    description =
      post.content
      |> strip_tags()
      |> truncate(300)
      |> blank_to(nil)

    %{
      title: "#{author} on #{instance}",
      description: description,
      image: post_image_url(post) || default_image(),
      site_name: instance
    }
  end

  defp profile_meta(identity) do
    instance = instance_name()
    name = identity.display_name || identity.handle

    description =
      identity.bio
      |> strip_tags()
      |> truncate(300)
      |> blank_to(nil)

    %{
      title: "#{name} (@#{identity.handle}) on #{instance}",
      description: description,
      image: identity.avatar_url || default_image(),
      site_name: instance
    }
  end

  defp legal_meta(title, markdown) do
    instance = instance_name()

    description =
      markdown
      |> strip_tags()
      |> truncate(300)
      |> blank_to(nil)

    %{
      title: "#{title} — #{instance}",
      description: description,
      image: default_image(),
      site_name: instance
    }
  end

  defp generic_meta do
    instance = instance_name()

    %{
      title: instance,
      description: nil,
      image: default_image(),
      site_name: instance
    }
  end

  defp instance_name do
    Config.get("instance_name", "HybridSocial")
  end

  defp default_image do
    base = HybridsocialWeb.Endpoint.url()

    case Config.get("instance_og_image") do
      url when is_binary(url) and url != "" ->
        if String.starts_with?(url, "http"), do: url, else: base <> ensure_leading_slash(url)

      _ ->
        base <> "/icons/icon.svg"
    end
  end

  defp ensure_leading_slash("/" <> _ = p), do: p
  defp ensure_leading_slash(p), do: "/" <> p

  defp post_image_url(%Post{} = post) do
    case post.media_attachments do
      list when is_list(list) ->
        list
        |> Enum.filter(&(is_nil(&1.deleted_at) and image_attachment?(&1)))
        |> case do
          [m | _] -> Hybridsocial.Media.media_url(m)
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp image_attachment?(%MediaFile{content_type: "image/" <> _}), do: true
  defp image_attachment?(_), do: false

  defp strip_tags(nil), do: ""

  defp strip_tags(text) when is_binary(text) do
    text
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

  defp truncate(_, _), do: ""

  defp blank_to("", fallback), do: fallback
  defp blank_to(text, _fallback) when is_binary(text), do: text
  defp blank_to(_, fallback), do: fallback

  # --- Private helpers ---

  defp hash_url(url) do
    normalized =
      url
      |> String.downcase()
      |> String.trim_trailing("/")

    :crypto.hash(:sha256, normalized)
    |> Base.encode16(case: :lower)
  end

  defp expired?(preview) do
    ttl = preview.ttl || 86400
    expires_at = DateTime.add(preview.fetched_at, ttl, :second)
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  defp fetch_and_store(url, url_hash) do
    case fetch_preview(url) do
      {:ok, meta} ->
        now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

        attrs = %{
          url_hash: url_hash,
          url: url,
          title: meta[:title],
          description: meta[:description],
          image_url: meta[:image],
          site_name: meta[:site_name],
          fetched_at: now
        }

        changeset = LinkPreview.changeset(%LinkPreview{}, attrs)

        case Repo.insert(changeset,
               on_conflict:
                 {:replace,
                  [:title, :description, :image_url, :site_name, :fetched_at, :updated_at]},
               conflict_target: [:url_hash]
             ) do
          {:ok, preview} -> {:ok, preview}
          {:error, changeset} -> {:error, changeset}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_meta_tags(html) do
    og_title = extract_og_tag(html, "og:title")
    og_description = extract_og_tag(html, "og:description")
    og_image = extract_og_tag(html, "og:image")
    og_site_name = extract_og_tag(html, "og:site_name")

    title = og_title || extract_title(html)
    description = og_description || extract_meta_description(html)

    # Meta tags often arrive HTML-encoded — Arabic / non-Latin pages
    # tend to use `&#x62f;` numeric refs in og:description, which would
    # otherwise reach the client as literal `&#x62f;` text and render
    # as ASCII gibberish. Decode once on store so every consumer sees
    # the real string.
    %{
      title: decode_entities(title),
      description: decode_entities(description),
      image: decode_entities(og_image),
      site_name: decode_entities(og_site_name)
    }
  end

  defp decode_entities(nil), do: nil

  defp decode_entities(str) when is_binary(str) do
    str
    |> decode_numeric_refs()
    |> decode_named_entities()
  end

  defp decode_numeric_refs(str) do
    # Hex (`&#x62f;`) then decimal (`&#1583;`). Hex first because the
    # decimal regex would otherwise consume `&#` and leave a stray
    # `xNNN;` behind.
    str
    |> then(
      &Regex.replace(~r/&#x([0-9a-fA-F]+);/, &1, fn _full, hex ->
        case Integer.parse(hex, 16) do
          {code, _} when code in 0..0x10FFFF -> <<code::utf8>>
          _ -> ""
        end
      end)
    )
    |> then(
      &Regex.replace(~r/&#(\d+);/, &1, fn _full, dec ->
        case Integer.parse(dec) do
          {code, _} when code in 0..0x10FFFF -> <<code::utf8>>
          _ -> ""
        end
      end)
    )
  end

  # `&amp;` last so we don't double-decode something like `&amp;lt;` into `<`.
  @named_entities [
    {"&lt;", "<"},
    {"&gt;", ">"},
    {"&quot;", "\""},
    {"&apos;", "'"},
    {"&#39;", "'"},
    {"&nbsp;", " "},
    {"&amp;", "&"}
  ]

  defp decode_named_entities(str) do
    Enum.reduce(@named_entities, str, fn {from, to}, acc ->
      String.replace(acc, from, to)
    end)
  end

  defp extract_og_tag(html, property) do
    # Match <meta property="og:xxx" content="..."> or <meta content="..." property="og:xxx">
    escaped = Regex.escape(property)

    patterns = [
      Regex.compile!(
        "<meta[^>]*property\\s*=\\s*[\"']#{escaped}[\"'][^>]*content\\s*=\\s*[\"']([^\"']*)[\"'][^>]*/?>",
        "is"
      ),
      Regex.compile!(
        "<meta[^>]*content\\s*=\\s*[\"']([^\"']*)[\"'][^>]*property\\s*=\\s*[\"']#{escaped}[\"'][^>]*/?>",
        "is"
      )
    ]

    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, html) do
        [_, value] -> value
        _ -> nil
      end
    end)
  end

  defp extract_title(html) do
    case Regex.run(~r/<title[^>]*>([^<]*)<\/title>/is, html) do
      [_, title] -> String.trim(title)
      _ -> nil
    end
  end

  defp extract_meta_description(html) do
    patterns = [
      ~r/<meta[^>]*name\s*=\s*["']description["'][^>]*content\s*=\s*["']([^"']*)["'][^>]*\/?>/is,
      ~r/<meta[^>]*content\s*=\s*["']([^"']*)["'][^>]*name\s*=\s*["']description["'][^>]*\/?>/is
    ]

    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, html) do
        [_, value] -> value
        _ -> nil
      end
    end)
  end

  defp resolve_host(host) do
    case parse_ip(host) do
      {:ok, ip} ->
        {:ok, ip}

      :error ->
        case :inet.getaddr(String.to_charlist(host), :inet) do
          {:ok, ip} -> {:ok, ip}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp parse_ip(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, ip} -> {:ok, ip}
      {:error, _} -> :error
    end
  end

  defp private_ip?({127, _, _, _}), do: true
  defp private_ip?({10, _, _, _}), do: true
  defp private_ip?({172, second, _, _}) when second >= 16 and second <= 31, do: true
  defp private_ip?({192, 168, _, _}), do: true
  defp private_ip?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp private_ip?(_), do: false

  # Other HybridSocial instances recognise this (any UA containing
  # "HybridSocial") and serve server-rendered OG; see Helpers.UserAgent.
  defp default_user_agent, do: Hybridsocial.Instance.user_agent("LinkPreview")
end
