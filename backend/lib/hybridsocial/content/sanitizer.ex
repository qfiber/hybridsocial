defmodule Hybridsocial.Content.Sanitizer do
  @moduledoc "Content sanitization: markdown to HTML, HTML allowlisting, link safety."

  @safe_tags ~w(p br a strong em b i code pre blockquote ul ol li span)
  @link_attrs %{
    "rel" => "nofollow noopener noreferrer",
    "target" => "_blank"
  }

  @allowed_schemes ["http://", "https://"]

  def sanitize_post_content(nil), do: nil
  def sanitize_post_content(""), do: ""

  def sanitize_post_content(content) do
    content
    |> markdown_to_html()
    |> sanitize_html()
    |> sanitize_links()
  end

  def markdown_to_html(text) do
    text
    |> String.trim()
    |> escape_html()
    |> convert_bold()
    |> convert_italic()
    |> convert_code()
    |> convert_links()
    |> convert_mentions()
    |> convert_hashtags()
    |> convert_paragraphs()
  end

  def sanitize_html(html) do
    # Strip any tags not in the allowlist
    Regex.replace(~r/<\/?([a-zA-Z][a-zA-Z0-9]*)[^>]*>/u, html, fn full, tag ->
      if String.downcase(tag) in @safe_tags do
        full
      else
        ""
      end
    end)
  end

  def sanitize_links(html) do
    Regex.replace(~r/<a\s[^>]*>/u, html, fn tag ->
      href =
        case Regex.run(~r/href="([^"]*)"/, tag) do
          [_, url] -> url
          _ -> "#"
        end

      cond do
        String.starts_with?(href, @allowed_schemes) ->
          safe_href = escape_attr(href)
          attrs = Enum.map_join(@link_attrs, " ", fn {k, v} -> ~s(#{k}="#{v}") end)
          ~s(<a href="#{safe_href}" #{attrs}>)

        String.starts_with?(href, "/") ->
          # Internal links (hashtags, mentions) — no rel/target needed
          safe_href = escape_attr(href)
          ~s(<a href="#{safe_href}">)

        true ->
          ~s(<a href="#">)
      end
    end)
  end

  # Escape HTML special characters in text content
  defp escape_html(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  # Escape for use inside HTML attribute values (double-quoted)
  defp escape_attr(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp convert_bold(text), do: Regex.replace(~r/\*\*(.+?)\*\*/u, text, "<strong>\\1</strong>")
  defp convert_italic(text), do: Regex.replace(~r/\*(.+?)\*/u, text, "<em>\\1</em>")
  defp convert_code(text), do: Regex.replace(~r/`(.+?)`/u, text, "<code>\\1</code>")

  defp convert_links(text) do
    Regex.replace(~r/\[([^\]]+)\]\(([^)]+)\)/u, text, fn _, label, url ->
      # Only allow http/https URLs — block javascript:, data:, etc.
      safe_url =
        if String.starts_with?(url, @allowed_schemes) do
          escape_attr(url)
        else
          "#"
        end

      safe_label = escape_html_content(label)
      attrs = Enum.map_join(@link_attrs, " ", fn {k, v} -> ~s(#{k}="#{v}") end)
      ~s(<a href="#{safe_url}" #{attrs}>#{safe_label}</a>)
    end)
  end

  defp convert_mentions(text) do
    Regex.replace(~r/@([a-zA-Z0-9_]+)(@[a-zA-Z0-9._-]+)?/u, text, fn full, _user, _domain ->
      # full is already HTML-escaped since escape_html ran first
      ~s(<span class="mention">#{full}</span>)
    end)
  end

  defp convert_hashtags(text) do
    Regex.replace(~r/#([a-zA-Z0-9_]+)/u, text, fn full, tag ->
      safe_tag = String.downcase(tag) |> URI.encode()
      ~s(<a href="/tags/#{safe_tag}" class="hashtag">#{full}</a>)
    end)
  end

  defp convert_paragraphs(text) do
    text
    |> String.split(~r/\n\n+/)
    |> Enum.map_join(fn para ->
      inner = String.replace(para, "\n", "<br>")
      "<p>#{inner}</p>"
    end)
  end

  # For content that was already HTML-escaped but needs extra safety in specific contexts
  defp escape_html_content(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
