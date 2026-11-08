defmodule Hybridsocial.Content.HtmlStripper do
  @moduledoc """
  Minimal HTML → plaintext for ingested remote content (DMs +
  direct-post notes). The post content path uses
  `Hybridsocial.Content.Sanitizer` for display HTML, but the plaintext
  column (`Message.content`, `Post.content` for remote origins) needs
  to be a clean string — that's what search, notifications, and
  plaintext clients read.

  Two previous implementations (`Inbox.strip_html` and whatever the
  post ingest was doing through ActivityMapper) diverged on how they
  handled `<br>`, paragraph breaks, and entity decoding. Consolidating
  here so both paths produce identical text for identical HTML.
  """

  @doc """
  Converts remote HTML to plaintext. Preserves paragraph + line
  breaks, strips any other markup, decodes the handful of entities
  that show up in federated content in practice.
  """
  def to_plaintext(nil), do: ""
  def to_plaintext(""), do: ""

  def to_plaintext(html) when is_binary(html) do
    html
    |> String.replace(~r/<br\s*\/?>/i, "\n")
    |> String.replace(~r/<\/p>\s*<p[^>]*>/i, "\n\n")
    |> String.replace(~r/<[^>]+>/, "")
    |> decode_entities()
    |> String.trim()
  end

  def to_plaintext(_), do: ""

  @doc """
  Decodes the handful of HTML entities our sanitizer emits and federated
  content uses in practice. For text that leaves HTML: anything that is
  escaped again on output (Svelte, `escape_html`) would otherwise show
  `&quot;` literally.

  `&amp;` goes last, so an escaped entity (`&amp;quot;`, i.e. the literal
  text "&quot;") decodes once, to "&quot;", not twice to a quote mark.
  """
  def decode_entities(text) when is_binary(text) do
    text
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&#x27;", "'")
    |> String.replace("&apos;", "'")
    |> String.replace("&nbsp;", " ")
    |> String.replace("&amp;", "&")
  end
end
