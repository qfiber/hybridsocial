defmodule Hybridsocial.Content.Sanitizer do
  @moduledoc "Content sanitization: markdown to HTML, HTML allowlisting, link safety."

  @safe_tags ~w(p br a strong em b i code pre blockquote ul ol li span)
  @link_attrs %{
    "rel" => "nofollow noopener noreferrer",
    "target" => "_blank"
  }

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
      # Extract href
      href = case Regex.run(~r/href="([^"]*)"/, tag) do
        [_, url] -> url
        _ -> "#"
      end

      if String.starts_with?(href, ["http://", "https://"]) do
        attrs = Enum.map_join(@link_attrs, " ", fn {k, v} -> ~s(#{k}="#{v}") end)
        ~s(<a href="#{href}" #{attrs}>)
      else
        ~s(<a href="#">)
      end
    end)
  end

  defp escape_html(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp convert_bold(text), do: Regex.replace(~r/\*\*(.+?)\*\*/u, text, "<strong>\\1</strong>")
  defp convert_italic(text), do: Regex.replace(~r/\*(.+?)\*/u, text, "<em>\\1</em>")
  defp convert_code(text), do: Regex.replace(~r/`(.+?)`/u, text, "<code>\\1</code>")

  defp convert_links(text) do
    Regex.replace(~r/\[([^\]]+)\]\(([^)]+)\)/u, text, fn _, label, url ->
      attrs = Enum.map_join(@link_attrs, " ", fn {k, v} -> ~s(#{k}="#{v}") end)
      ~s(<a href="#{url}" #{attrs}>#{label}</a>)
    end)
  end

  defp convert_mentions(text) do
    Regex.replace(~r/@([a-zA-Z0-9_]+)(@[a-zA-Z0-9._-]+)?/u, text, fn full, _user, _domain ->
      ~s(<span class="mention">#{full}</span>)
    end)
  end

  defp convert_hashtags(text) do
    Regex.replace(~r/#([a-zA-Z0-9_]+)/u, text, fn full, tag ->
      ~s(<a href="/tags/#{String.downcase(tag)}" class="hashtag">#{full}</a>)
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
end
