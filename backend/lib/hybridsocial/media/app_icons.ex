defmodule Hybridsocial.Media.AppIcons do
  @moduledoc """
  Derives the installed-app icons (web app manifest + iOS home screen) from an
  instance's favicon.

  Browsers want square PNG launcher icons at fixed sizes (192 and 512, plus a
  `maskable` 512 with the glyph inside the safe zone), and iOS wants a 180px
  opaque PNG. A favicon is usually none of those, so whatever the admin uploads
  is rasterized once, at upload time, with libvips (the same tool as
  `Media.EmailLogo`) and stored through the media storage backend.

  Sizes are never invented: an SVG source scales to anything, but a raster
  smaller than #{512}px on its longest side would only produce blurry icons, so
  it derives nothing and the instance keeps the built-in defaults.

  The URLs are stored in config together with the favicon URL they were derived
  from (`app_icon_source`). `icons/0` only returns them while that source is
  still the configured favicon, so replacing or clearing the favicon can never
  leave stale icons behind.
  """
  require Logger

  alias Hybridsocial.Config
  alias Hybridsocial.Media.Storage

  @min_raster_px 512
  # Maskable icons are cropped to a circle (or squircle) of 80% diameter; keep
  # the glyph inside that safe zone.
  @maskable_glyph_px 410
  @white "255 255 255 255"
  @transparent "0 0 0 0"
  @png_suffix "[strip,compression=9]"

  # {config key, output size, glyph size, background (nil = transparent)}
  @variants [
    {"app_icon_180_url", 180, 180, @white},
    {"app_icon_192_url", 192, 192, nil},
    {"app_icon_512_url", 512, 512, nil},
    {"app_icon_maskable_url", 512, @maskable_glyph_px, @white}
  ]

  @doc """
  The derived icons for the current favicon, or `nil` when there are none
  (no favicon, an unusable one, or icons left over from an older favicon).
  """
  def icons do
    favicon = Config.get("theme_favicon_url", "")
    source = Config.get("app_icon_source", "")

    urls = for {key, _, _, _} <- @variants, do: Config.get(key, "")

    if is_binary(favicon) and favicon != "" and source == favicon and
         Enum.all?(urls, &(is_binary(&1) and &1 != "")) do
      [apple_touch, icon_192, icon_512, maskable_512] = urls

      %{
        apple_touch: apple_touch,
        icon_192: icon_192,
        icon_512: icon_512,
        maskable_512: maskable_512
      }
    end
  end

  @doc """
  Derive from an uploaded favicon and record the icons against `source_url`
  (the favicon's stored URL). Best-effort: `{:error, reason}` on any hitch,
  `{:error, :too_small}` for a raster below #{@min_raster_px}px.
  """
  def derive(%Plug.Upload{path: src, content_type: content_type}, source_url)
      when is_binary(source_url) do
    derive_and_store(src, ext_for(content_type), source_url)
  end

  def derive(_, _), do: {:error, :invalid_upload}

  @doc """
  Derive from an already-stored favicon URL. For backfilling an instance
  whose favicon was uploaded before app icons existed:

      Hybridsocial.Media.AppIcons.derive_from_url(
        Hybridsocial.Config.get("theme_favicon_url")
      )
  """
  def derive_from_url(url) when is_binary(url) and url != "" do
    case Hybridsocial.HTTP.get(url) do
      {:ok, %{status_code: 200, body: body}} when is_binary(body) and byte_size(body) > 0 ->
        ext = url_ext(url)
        src = tmp("app_icon_src", ext)
        File.write!(src, body)

        try do
          derive_and_store(src, ext, url)
        after
          File.rm(src)
        end

      other ->
        Logger.warning("[app_icons] fetch of #{url} failed: #{inspect(other)}")
        {:error, :fetch_failed}
    end
  rescue
    e ->
      Logger.warning("[app_icons] derive_from_url failed: #{inspect(e)}")
      {:error, :exception}
  end

  def derive_from_url(_), do: {:error, :invalid_url}

  # ── internals ─────────────────────────────────────────────────────

  defp derive_and_store(src_path, ext, source_url) do
    input = tmp("app_icon_in", ext)

    try do
      File.cp!(src_path, input)

      with :ok <- check_size(input, ext),
           {:ok, urls} <- render_all(input) do
        Enum.each(urls, fn {key, url} -> Config.set(key, url) end)
        Config.set("app_icon_source", source_url)
        {:ok, Map.new(urls)}
      end
    rescue
      e ->
        Logger.warning("[app_icons] derive failed: #{inspect(e)}")
        {:error, :exception}
    after
      File.rm(input)
    end
  end

  # Vector sources render crisply at any size.
  defp check_size(_input, "svg"), do: :ok

  defp check_size(input, _ext) do
    with {:ok, w} <- header(input, "width"),
         {:ok, h} <- header(input, "height") do
      if max(w, h) >= @min_raster_px, do: :ok, else: {:error, :too_small}
    end
  end

  defp header(input, field) do
    case System.cmd("vipsheader", ["-f", field, input], stderr_to_stdout: true) do
      {out, 0} ->
        case Integer.parse(String.trim(out)) do
          {n, _} -> {:ok, n}
          :error -> {:error, :unreadable}
        end

      {msg, code} ->
        Logger.warning("[app_icons] vipsheader exit #{code}: #{String.trim(msg)}")
        {:error, :unreadable}
    end
  end

  defp render_all(input) do
    Enum.reduce_while(@variants, {:ok, []}, fn {key, size, glyph, bg}, {:ok, acc} ->
      case render(input, size, glyph, bg) do
        {:ok, url} -> {:cont, {:ok, [{key, url} | acc]}}
        err -> {:halt, err}
      end
    end)
  end

  # Fit the source into a `glyph`-px box (never upscaling a raster; the size
  # check guarantees it's large enough), normalize it to 4-band sRGB (a JPEG
  # has no alpha and a grayscale PNG has one band, and `gravity`'s background
  # vector must match the band count), then centre it on an exact
  # `size`x`size` canvas, so a non-square favicon still yields a square icon.
  defp render(input, size, glyph, bg) do
    fitted = tmp("app_icon_fit", "png")
    srgb = tmp("app_icon_srgb", "png")
    rgba = tmp("app_icon_rgba", "png")
    output = tmp("app_icon_out", "png")
    flat = tmp("app_icon_flat", "png")

    try do
      with {:ok, _} <-
             vips("vipsthumbnail", [input, "--size", "#{glyph}x#{glyph}>", "-o", fitted]),
           {:ok, _} <- vips("vips", ["colourspace", fitted, srgb, "srgb"]),
           :ok <- ensure_alpha(srgb, rgba),
           {:ok, _} <-
             vips("vips", [
               "gravity",
               rgba,
               output,
               "centre",
               "#{size}",
               "#{size}",
               "--extend",
               "background",
               "--background",
               bg || @transparent
             ]),
           {:ok, final} <- maybe_flatten(output, flat, bg) do
        store(final, "app-icon-#{size}.png")
      end
    after
      Enum.each([fitted, srgb, rgba, output, flat], &File.rm/1)
    end
  end

  defp ensure_alpha(src, dest) do
    case header(src, "bands") do
      {:ok, 3} ->
        with {:ok, _} <- vips("vips", ["bandjoin_const", src, dest, "255"]), do: :ok

      {:ok, _} ->
        File.cp!(src, dest)
        :ok

      err ->
        err
    end
  end

  # iOS draws a transparent touch icon on black, so the opaque variants are
  # flattened onto their background. Transparent ones are just re-encoded
  # with metadata stripped.
  defp maybe_flatten(src, dest, nil) do
    with {:ok, _} <- vips("vips", ["copy", src, dest <> @png_suffix]), do: {:ok, dest}
  end

  defp maybe_flatten(src, dest, _bg) do
    with {:ok, _} <-
           vips("vips", ["flatten", src, dest <> @png_suffix, "--background", "255 255 255"]) do
      {:ok, dest}
    end
  end

  defp vips(cmd, args) do
    case System.cmd(cmd, args, stderr_to_stdout: true) do
      {out, 0} ->
        {:ok, out}

      {msg, code} ->
        Logger.warning("[app_icons] #{cmd} exit #{code}: #{String.trim(msg)}")
        {:error, :rasterize_failed}
    end
  end

  # No owner / media row: like the email logo, these are instance assets
  # referenced from config, stored straight through the backend.
  defp store(png_path, filename) do
    upload = %Plug.Upload{path: png_path, content_type: "image/png", filename: filename}

    case Storage.store(upload, nil) do
      {:ok, storage_path} -> {:ok, Storage.url(storage_path)}
      {:error, _} = err -> err
    end
  end

  defp tmp(prefix, ext) do
    Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}.#{ext}")
  end

  defp url_ext(url) do
    case url
         |> URI.parse()
         |> Map.get(:path)
         |> to_string()
         |> Path.extname()
         |> String.trim_leading(".") do
      "" -> "bin"
      ext -> String.downcase(ext)
    end
  end

  defp ext_for("image/svg+xml"), do: "svg"
  defp ext_for("image/png"), do: "png"
  defp ext_for("image/jpeg"), do: "jpg"
  defp ext_for("image/webp"), do: "webp"
  defp ext_for("image/gif"), do: "gif"
  defp ext_for(_), do: "bin"
end
