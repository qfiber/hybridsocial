defmodule Hybridsocial.Media.PlaceholderSvg do
  @moduledoc """
  Self-contained SVG placeholders served in place of media the proxy
  refuses or can't stream: infected content flagged by the antivirus
  scanner, the "scanner unreachable" fail-closed state (both in a danger
  palette), and remote media the origin wouldn't serve (neutral).

  Served with `Content-Type: image/svg+xml` so an `<img>` tag renders
  them inline where a broken image icon would have been — strictly
  better UX than a blank frame or a 4xx with no body. `<video>`
  players obviously can't play an SVG, but setting `src` to this
  still surfaces a visible "something was removed" frame instead of
  silently failing.

  Styling loosely matches the NSFW overlay (layered gradient waves +
  frost glass + centered badge + text) but recolored into the danger
  palette (red/orange) because this is a harder warning — the user
  is being actively protected from something, not just pre-warned.
  """

  @doc "Full SVG document for the 'malware detected' placeholder."
  def infected do
    render(
      "MALWARE",
      "Content removed",
      "This file was blocked by our antivirus scanner before it could reach you."
    )
  end

  @doc "Full SVG for the 'scanner unreachable' placeholder."
  def scanner_unreachable do
    render(
      "BLOCKED",
      "Scanner unavailable",
      "The antivirus scanner is currently unreachable. This media can't be served until it's verified clean."
    )
  end

  @doc """
  Neutral placeholder for remote media we couldn't fetch: the origin
  refused (e.g. a CDN's bot wall answering 403), timed out or was
  unreachable. `kind` (`:image`, `:video`, `:audio`) picks the title.
  Calm slate palette, not the danger one: nothing was blocked for the
  viewer's safety, the source just wouldn't share it.
  """
  def unavailable(kind \\ :image) do
    title =
      case kind do
        :video -> "Video not available"
        :audio -> "Audio not available"
        _ -> "Image not available"
      end

    render("UNAVAILABLE", title, "The original site didn't allow it to be loaded.", :neutral)
  end

  # ── Internal ───────────────────────────────────────────────────────

  # Aspect-ratio-independent: viewBox is 16:9 but `preserveAspectRatio="xMidYMid slice"`
  # on the consumer's <img> will crop gracefully. We keep the badge
  # + text anchored from center so it stays visible at any crop.
  @palettes %{
    danger: %{
      grad: ["#450a0a", "#7f1d1d", "#b91c1c"],
      glow: "#f87171",
      waves: ["#ef4444", "#dc2626", "#f97316"],
      stroke: "#fca5a5",
      glyph_fill: "#fecaca",
      glyph_ink: "#7f1d1d",
      badge_bg: "#fee2e2",
      badge_ink: "#991b1b",
      title: "#fff5f5",
      subtitle: "#fecaca"
    },
    neutral: %{
      grad: ["#0f172a", "#1e293b", "#334155"],
      glow: "#94a3b8",
      waves: ["#64748b", "#475569", "#94a3b8"],
      stroke: "#cbd5e1",
      glyph_fill: "#e2e8f0",
      glyph_ink: "#334155",
      badge_bg: "#e2e8f0",
      badge_ink: "#334155",
      title: "#f8fafc",
      subtitle: "#cbd5e1"
    }
  }

  # Warning shield for the danger palette; a picture frame with a slash
  # for "not available".
  defp glyph(:danger, c) do
    """
        <path d="M 0,-34 L 26,-22 L 26,4 C 26,20 14,32 0,36 C -14,32 -26,20 -26,4 L -26,-22 Z"
              fill="#{c.glyph_fill}" fill-opacity="0.95" />
        <rect x="-2.5" y="-18" width="5" height="22" rx="2" fill="#{c.glyph_ink}" />
        <circle cx="0" cy="14" r="3" fill="#{c.glyph_ink}" />
    """
  end

  defp glyph(:neutral, c) do
    """
        <rect x="-30" y="-26" width="60" height="48" rx="7" fill="#{c.glyph_fill}" fill-opacity="0.95" />
        <circle cx="-12" cy="-10" r="6" fill="#{c.glyph_ink}" />
        <path d="M -24,16 L -6,-2 L 6,10 L 14,2 L 24,16 Z" fill="#{c.glyph_ink}" />
        <line x1="-34" y1="30" x2="34" y2="-34" stroke="#{c.glyph_ink}" stroke-width="5" stroke-linecap="round" />
    """
  end

  defp render(badge, title, subtitle, palette \\ :danger) do
    c = Map.fetch!(@palettes, palette)
    [g0, g1, g2] = c.grad
    [w0, w1, w2] = c.waves

    """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 450" preserveAspectRatio="xMidYMid slice" role="img" aria-label="#{escape(title)}: #{escape(subtitle)}">
      <defs>
        <linearGradient id="danger-grad" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0%" stop-color="#{g0}" stop-opacity="1" />
          <stop offset="60%" stop-color="#{g1}" stop-opacity="1" />
          <stop offset="100%" stop-color="#{g2}" stop-opacity="1" />
        </linearGradient>
        <radialGradient id="danger-glow" cx="0.5" cy="0.5" r="0.7">
          <stop offset="0%" stop-color="#{c.glow}" stop-opacity="0.35" />
          <stop offset="100%" stop-color="#{c.glow}" stop-opacity="0" />
        </radialGradient>
        <filter id="glass-blur" x="-5%" y="-5%" width="110%" height="110%">
          <feGaussianBlur stdDeviation="10" />
        </filter>
      </defs>

      <!-- base fill -->
      <rect width="800" height="450" fill="url(#danger-grad)" />

      <!-- animated-looking layered waves, matching the NSFW overlay
           in the chosen palette. These are static paths — no
           <animateTransform> — because many image-rendering clients
           (mail clients, thumbnailers) don't execute SMIL. -->
      <g opacity="0.18">
        <path d="M0,320 Q200,260 400,320 T800,320 L800,450 L0,450 Z" fill="#{w0}" />
      </g>
      <g opacity="0.14">
        <path d="M0,360 Q250,300 500,360 T800,340 L800,450 L0,450 Z" fill="#{w1}" />
      </g>
      <g opacity="0.10">
        <path d="M0,250 Q180,210 380,250 T800,230 L800,450 L0,450 Z" fill="#{w2}" />
      </g>

      <!-- center radial glow -->
      <rect width="800" height="450" fill="url(#danger-glow)" />

      <!-- frost-glass panel behind the text so it stays legible on
           any crop -->
      <rect x="140" y="150" width="520" height="180" rx="20"
            fill="#0a0a0a" fill-opacity="0.45" />
      <rect x="140" y="150" width="520" height="180" rx="20"
            fill="none" stroke="#{c.stroke}" stroke-opacity="0.35" stroke-width="1" />

      <!-- glyph: warning shield (danger) or crossed-out picture (neutral) -->
      <g transform="translate(400, 200)">
    #{glyph(palette, c)}      </g>

      <!-- badge -->
      <g transform="translate(400, 252)">
        <rect x="-60" y="-14" width="120" height="24" rx="12"
              fill="#{c.badge_bg}" />
        <text x="0" y="2" text-anchor="middle"
              font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif"
              font-size="12" font-weight="800"
              letter-spacing="1.5"
              fill="#{c.badge_ink}">#{escape(badge)}</text>
      </g>

      <!-- title -->
      <text x="400" y="285" text-anchor="middle"
            font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif"
            font-size="22" font-weight="700"
            fill="#{c.title}">#{escape(title)}</text>

      <!-- subtitle — wrapped via two tspan lines if needed. For
           simplicity we truncate at ~70 chars; admins can still see
           the full detail in the audit log. -->
      <text x="400" y="313" text-anchor="middle"
            font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif"
            font-size="13" fill="#{c.subtitle}" fill-opacity="0.85">
        <tspan x="400" dy="0">#{escape(truncate(subtitle, 80))}</tspan>
      </text>
    </svg>
    """
  end

  # SVG text is XML — always escape the five special chars so a
  # signature name that contains `<` or `&` doesn't break rendering.
  defp escape(str) when is_binary(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  defp escape(other), do: escape(to_string(other))

  defp truncate(str, max) when byte_size(str) <= max, do: str
  defp truncate(str, max), do: String.slice(str, 0, max - 1) <> "…"
end
