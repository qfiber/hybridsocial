defmodule Hybridsocial.Content.LinkPreviews do
  @moduledoc """
  Context module for link preview fetching and caching.
  """
  alias Hybridsocial.Repo
  alias Hybridsocial.Content.LinkPreview

  @user_agent "HybridSocial/1.0 (LinkPreview)"
  @fetch_timeout 5_000
  @max_response_size 1_048_576

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
    with {:ok, _url} <- validate_url(url) do
      headers = [{"User-Agent", @user_agent}]

      options = [
        recv_timeout: @fetch_timeout,
        timeout: @fetch_timeout,
        max_body_length: @max_response_size
      ]

      case HTTPoison.get(url, headers, options) do
        {:ok, %HTTPoison.Response{status_code: status, body: body}}
        when status >= 200 and status < 300 ->
          {:ok, parse_meta_tags(body)}

        {:ok, %HTTPoison.Response{status_code: status}} ->
          {:error, {:http_error, status}}

        {:error, %HTTPoison.Error{reason: reason}} ->
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
  Extracts the first URL from a post's content and fetches its preview.
  """
  def preview_for_post(post) do
    case extract_urls(post.content || "") do
      [first_url | _] -> get_or_fetch(first_url)
      [] -> {:error, :no_urls}
    end
  end

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
               on_conflict: {:replace, [:title, :description, :image_url, :site_name, :fetched_at, :updated_at]},
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

    %{
      title: title,
      description: description,
      image: og_image,
      site_name: og_site_name
    }
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
end
