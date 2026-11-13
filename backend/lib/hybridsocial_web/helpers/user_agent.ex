defmodule HybridsocialWeb.Helpers.UserAgent do
  @moduledoc """
  User-Agent classification for the social-sharing crawler layer.

  Crawlers don't execute JavaScript, so they need a server-rendered HTML
  shell with OG/Twitter Card meta tags to unfurl links into previews.
  Regular browsers bypass this path entirely — the SPA handles them.

  The list below is intentionally conservative: match only the strings
  the platforms actually send. False positives would break real users;
  false negatives just mean a missed unfurl (recoverable — the user can
  re-share).
  """

  @crawler_substrings [
    "facebookexternalhit",
    "facebot",
    "twitterbot",
    "linkedinbot",
    "slackbot",
    "slack-imgproxy",
    "whatsapp",
    "telegrambot",
    "telegram",
    "discordbot",
    "skypeuripreview",
    "redditbot",
    "pinterest",
    "bingbot",
    "googlebot",
    "google-structured-data-testing-tool",
    "yandexbot",
    "duckduckbot",
    "applebot",
    "baiduspider",
    "archive.org_bot",
    "bitlybot",
    "mastodon",
    "pleroma",
    "misskey",
    "akkoma",
    "iframely",
    "embedly",
    "lightbot",
    "signal",
    "xing-contenttabreceiver",
    "vkshare",
    "w3c_validator",
    # Other HybridSocial instances fetching our URLs for link previews
    # send `HybridSocial LinkPreview/<version> (+<url>)`. Treat them as crawlers so
    # they get server-rendered OG instead of the SPA handoff redirect.
    "hybridsocial"
  ]

  @doc """
  True when the request's User-Agent looks like a social-sharing crawler
  or link-preview bot that needs an OG shell.
  """
  def crawler?(%Plug.Conn{} = conn) do
    case Plug.Conn.get_req_header(conn, "user-agent") do
      [ua | _] -> crawler_ua?(ua)
      _ -> false
    end
  end

  def crawler_ua?(nil), do: false

  def crawler_ua?(ua) when is_binary(ua) do
    downcased = String.downcase(ua)
    Enum.any?(@crawler_substrings, &String.contains?(downcased, &1))
  end

  def crawler_ua?(_), do: false
end
