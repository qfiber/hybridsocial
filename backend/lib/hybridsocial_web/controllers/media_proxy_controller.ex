defmodule HybridsocialWeb.MediaProxyController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Antivirus
  alias Hybridsocial.Config
  alias Hybridsocial.Federation.InstancePolicy
  alias Hybridsocial.Media.Backends.Local
  alias Hybridsocial.Media.InfectedTracker
  alias Hybridsocial.Media.MediaProxy
  alias Hybridsocial.Media.MediaProxyCache
  alias Hybridsocial.Media.PlaceholderSvg
  alias Hybridsocial.Repo

  require Logger

  # Only allow media MIME types through the proxy. A compromised or hostile
  # upstream cannot trick the browser into rendering text/html as an HTML
  # page even if it omits nosniff; anything off-allowlist is forced to
  # application/octet-stream.
  @safe_media_prefixes ["image/", "video/", "audio/"]

  # Domains under one of these policies have their media refused
  # outright. `silence` and `force_nsfw` deliberately don't block —
  # they're about visibility, not security.
  @blocking_policies ~w(suspend block_media)

  # Hard caps for an upstream fetch.
  @fetch_timeout_ms 5_000

  # Max bytes for a single proxied remote fetch. Runtime-configurable and
  # defaults to the platform's video upload ceiling (100 MB) so a remote
  # video isn't rejected when a local upload of the same size would be
  # accepted — the old hardcoded 50 MB cap bounced ordinary remote videos
  # (see issue #24). Still bounded so a hostile upstream can't fill disk.
  @default_max_file_bytes 100_000_000

  defp max_file_bytes do
    case Config.get("media_proxy_max_bytes", @default_max_file_bytes) do
      n when is_integer(n) and n > 0 -> n
      _ -> @default_max_file_bytes
    end
  end

  @doc "Proxy a remote media URL through the local server."
  # sobelow_skip ["XSS.SendResp", "Traversal.SendFile"]
  def show(conn, %{"signature" => signature, "encoded_url" => encoded_url}) do
    with {:ok, remote_url} <- MediaProxy.verify_url(signature, encoded_url),
         :ok <- validate_remote_url(remote_url),
         :ok <- check_instance_policy(remote_url) do
      # Kept for the error path: a refused fetch is answered with a
      # placeholder titled for the media kind (see handle_error/2).
      conn = assign(conn, :proxy_remote_url, remote_url)

      case MediaProxyCache.lookup(remote_url) do
        {:hit, %{path: path, content_type: content_type, hash: hash}} ->
          # Bump LRU bookkeeping but don't block the response on the
          # write — touch failures are harmless (just costs us a
          # re-fetch later if eviction comes for it before we
          # rewrite the timestamp).
          Task.start(fn -> MediaProxyCache.touch(hash) end)

          conn
          |> put_response_headers(sanitize_content_type(content_type))
          |> serve_with_range(path)

        :miss ->
          serve_and_cache(conn, remote_url)
      end
    else
      {:error, reason} -> handle_error(conn, reason)
    end
  end

  # sobelow_skip ["Traversal.SendFile"]
  defp serve_and_cache(conn, remote_url) do
    # Stream the upstream body straight to a tmp file (no in-memory
    # buffering), AV-scan the file once, then promote it into the
    # cache and serve via send_file. From this point on every hit
    # for the URL skips both the network and the scanner.
    #
    # Safe send_file: cache_path is built by MediaProxyCache from a
    # SHA-256 of the verified remote URL — never user input.
    with {:ok, %{tmp_path: tmp_path, content_type: ct, byte_size: size}} <-
           stream_remote_to_tmp(remote_url),
         :ok <- scan_file_or_cleanup(tmp_path) do
      content_type = sanitize_content_type(ct)

      if MediaProxyCache.enabled?() do
        serve_cached(conn, remote_url, tmp_path, content_type, size)
      else
        serve_uncached(conn, tmp_path, content_type)
      end
    else
      {:error, reason} -> handle_error(conn, reason)
    end
  end

  # sobelow_skip ["Traversal.SendFile"]
  defp serve_cached(conn, remote_url, tmp_path, content_type, size) do
    case MediaProxyCache.store_path(remote_url, tmp_path, content_type, size) do
      {:ok, %{path: cache_path}} ->
        conn
        |> put_response_headers(content_type)
        |> serve_with_range(cache_path)

      {:error, reason} ->
        handle_error(conn, reason)
    end
  end

  # With `media_proxy_cache_enabled` off there's no cache file to promote
  # into, so serve the scanned tmp download directly and delete it once
  # it's sent. `after` also covers a client that hangs up mid-transfer.
  # (Handing the tmp file to `store_path/4` here used to delete it and
  # return a bare `:ok` that matched no clause: a 500 on every request.)
  # sobelow_skip ["Traversal.SendFile", "Traversal.FileModule"]
  # Safe: tmp_path comes from new_tmp_path/0 (random name in our own dir).
  defp serve_uncached(conn, tmp_path, content_type) do
    conn
    |> put_response_headers(content_type)
    |> serve_with_range(tmp_path)
  after
    File.rm(tmp_path)
  end

  # send_file/3 ignores Range headers — Plug.Static handles them but
  # we're outside that path. Parse the header ourselves so video
  # seeking works on cached entries (browsers issue Range on every
  # seek; without 206 they have to re-download from byte 0).
  # sobelow_skip ["Traversal.SendFile"]
  defp serve_with_range(conn, path) do
    conn = put_resp_header(conn, "accept-ranges", "bytes")

    case get_req_header(conn, "range") do
      [range] ->
        case File.stat(path) do
          {:ok, %File.Stat{size: file_size}} ->
            send_range_or_full(conn, path, range, file_size)

          {:error, _} ->
            send_file(conn, 200, path)
        end

      _ ->
        send_file(conn, 200, path)
    end
  end

  # sobelow_skip ["Traversal.SendFile"]
  defp send_range_or_full(conn, path, range, file_size) do
    with %{"bytes" => bytes} <- Plug.Conn.Utils.params(range),
         {range_start, range_end} <- parse_range(bytes, file_size) do
      length = range_end - range_start + 1

      conn
      |> put_resp_header("content-range", "bytes #{range_start}-#{range_end}/#{file_size}")
      |> send_file(206, path, range_start, length)
    else
      _ -> send_file(conn, 200, path)
    end
  end

  defp parse_range("-" <> rest, file_size) do
    case Integer.parse(rest) do
      {last, ""} when last > 0 and last <= file_size -> {file_size - last, file_size - 1}
      _ -> :error
    end
  end

  defp parse_range(range, file_size) do
    case Integer.parse(range) do
      {first, "-"} when first >= 0 and first < file_size ->
        {first, file_size - 1}

      {first, "-" <> rest} when first >= 0 and first < file_size ->
        case Integer.parse(rest) do
          {last, ""} when last >= first -> {first, min(last, file_size - 1)}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  # Safe: tmp_path comes from new_tmp_path/0 — the fixed uploads dir joined
  # with a crypto.strong_rand_bytes URL-base64 name ([A-Za-z0-9_-] only, no
  # path separators or dots). No request data reaches the file path.
  defp stream_remote_to_tmp(url) do
    headers = [
      {"User-Agent", "HybridSocial MediaProxy/0.1.0"},
      {"Accept", "*/*"}
    ]

    max_bytes = max_file_bytes()

    with {:ok, tmp_path} <- new_tmp_path(),
         {:ok, file} <- File.open(tmp_path, [:write, :binary, :raw]) do
      # Stream the body straight to the tmp file (no in-memory buffering),
      # aborting the moment we cross the size cap so a hostile upstream
      # can't exhaust disk. Req's `into` fun runs per chunk; returning
      # :halt stops the download and releases the socket.
      collector = fn {:data, chunk}, {req, resp} ->
        written = resp.private[:bytes] || 0

        cond do
          resp.status not in 200..299 ->
            {:halt, {req, resp}}

          written + byte_size(chunk) > max_bytes ->
            {:halt, {req, put_resp_private(resp, :too_large, true)}}

          true ->
            case IO.binwrite(file, chunk) do
              :ok -> {:cont, {req, put_resp_private(resp, :bytes, written + byte_size(chunk))}}
              _ -> {:halt, {req, put_resp_private(resp, :write_error, true)}}
            end
        end
      end

      result =
        case [
               method: :get,
               url: url,
               headers: headers,
               redirect: true,
               max_redirects: 3,
               receive_timeout: @fetch_timeout_ms,
               connect_options: [timeout: @fetch_timeout_ms],
               decode_body: false,
               retry: false,
               into: collector
             ]
             |> Keyword.merge(req_test_options())
             |> Req.request() do
          {:ok, resp} ->
            cond do
              resp.status not in 200..299 ->
                {:error, {:http_error, resp.status}}

              resp.private[:too_large] ->
                {:error, :too_large}

              resp.private[:write_error] ->
                {:error, :write_failed}

              true ->
                {:ok,
                 %{
                   tmp_path: tmp_path,
                   content_type: content_type_from(resp),
                   byte_size: resp.private[:bytes] || 0
                 }}
            end

          {:error, exception} ->
            {:error, Map.get(exception, :reason, exception)}
        end

      File.close(file)
      finalize_stream(result, tmp_path)
    end
  end

  # Test seam: lets tests route the upstream fetch to a `Req.Test` stub.
  # Unset (empty) outside tests.
  defp req_test_options, do: Application.get_env(:hybridsocial, :media_proxy_req_options, [])

  defp put_resp_private(resp, key, value) do
    %{resp | private: Map.put(resp.private, key, value)}
  end

  defp content_type_from(resp) do
    case resp.headers["content-type"] do
      [ct | _] -> ct
      ct when is_binary(ct) -> ct
      _ -> "application/octet-stream"
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  # Safe: dir is Local.uploads_dir() joined with fixed literals, and the
  # file name is a crypto-random base64 token. No user input in the path.
  defp new_tmp_path do
    dir = Path.join([Local.uploads_dir(), "proxy_cache", ".tmp"])

    case File.mkdir_p(dir) do
      :ok ->
        name = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
        {:ok, Path.join(dir, name)}

      err ->
        err
    end
  end

  # On any error path the partial download is unusable — make sure
  # the tmp file doesn't leak even if the request blew up
  # mid-stream. tmp_path is built from random bytes inside our own
  # uploads dir (see new_tmp_path/0) so the File.rm is safe.
  # sobelow_skip ["Traversal.FileModule"]
  defp finalize_stream({:ok, _} = ok, _tmp_path), do: ok

  # sobelow_skip ["Traversal.FileModule"]
  defp finalize_stream({:error, _} = err, tmp_path) do
    File.rm(tmp_path)
    err
  end

  # tmp_path comes from new_tmp_path/0 (random bytes under
  # uploads_dir) — never user input. The File.rm calls below are
  # safe; suppressing sobelow's pattern-based traversal alarm.
  # sobelow_skip ["Traversal.FileModule"]
  defp scan_file_or_cleanup(tmp_path) do
    case Antivirus.scan_file(tmp_path) do
      :ok ->
        :ok

      {:error, {:infected, _signature_name}} = err ->
        # Bubble infection up: handle_error/2 logs, records audit
        # metadata, and renders the placeholder.
        File.rm(tmp_path)
        err

      {:error, :unreachable} ->
        File.rm(tmp_path)
        {:error, :av_unreachable}

      {:error, other} ->
        File.rm(tmp_path)
        {:error, {:av_error, other}}
    end
  end

  defp put_response_headers(conn, content_type) do
    conn
    |> put_resp_header("content-type", content_type)
    |> put_resp_header("cache-control", "public, max-age=86400, immutable")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("content-security-policy", "default-src 'none'")
  end

  defp handle_error(conn, :invalid_signature),
    do: conn |> put_status(403) |> json(%{error: "Invalid signature"})

  defp handle_error(conn, :invalid_url),
    do: conn |> put_status(400) |> json(%{error: "Invalid URL"})

  defp handle_error(conn, :private_host),
    do: conn |> put_status(403) |> json(%{error: "Forbidden"})

  defp handle_error(conn, :instance_blocked),
    do: conn |> put_status(403) |> json(%{error: "Origin instance is blocked"})

  # Infected remote media: log, record for audit/trending (no
  # identity — it's a federated stranger, not one of our users), then
  # serve a friendly "content removed" SVG in place of the bytes.
  # Served as 200 image/svg+xml so <img> renders the placeholder
  # inline instead of showing a broken-image icon; a 4xx here would
  # look like the server itself failed.
  defp handle_error(conn, {:infected, signature_name}) do
    Logger.warning("Media proxy refused infected payload signature=#{signature_name}")
    InfectedTracker.record(nil, signature_name, "proxy", 0)
    send_placeholder(conn, PlaceholderSvg.infected())
  end

  # Scanner down: fail-closed at the byte level, but still render a
  # recognisable placeholder so the consumer's UI doesn't look broken.
  defp handle_error(conn, :av_unreachable) do
    Logger.warning("Media proxy refused payload — antivirus scanner unreachable")
    send_placeholder(conn, PlaceholderSvg.scanner_unreachable())
  end

  defp handle_error(conn, {:av_error, inner}) do
    Logger.warning("Media proxy refused payload — antivirus error: #{inspect(inner)}")
    send_placeholder(conn, PlaceholderSvg.scanner_unreachable())
  end

  defp handle_error(conn, :too_large) do
    # Upstream sent more than @max_file_bytes — bail out rather
    # than fill the cache with one giant blob.
    conn |> put_status(413) |> json(%{error: "Remote media exceeds size limit"})
  end

  # The origin refused (a CDN bot wall answering 403, a 404, a 5xx), timed
  # out or was unreachable. Serve a neutral "not available" image instead of
  # an error so the post shows a clean frame rather than a broken-image
  # icon. `send_placeholder/2` marks it no-store, so the real media appears
  # as soon as the origin serves it.
  defp handle_error(conn, reason) do
    Logger.warning("Media proxy fetch failed: #{inspect(reason)}")

    send_placeholder(
      conn,
      PlaceholderSvg.unavailable(media_kind(conn.assigns[:proxy_remote_url]))
    )
  end

  @video_exts ~w(.mp4 .webm .mov .m4v .ogv)
  @audio_exts ~w(.mp3 .ogg .oga .m4a .wav .opus .flac)

  defp media_kind(url) when is_binary(url) do
    ext =
      url |> URI.parse() |> Map.get(:path) |> to_string() |> Path.extname() |> String.downcase()

    cond do
      ext in @video_exts -> :video
      ext in @audio_exts -> :audio
      true -> :image
    end
  end

  defp media_kind(_), do: :image

  # sobelow_skip ["XSS.SendResp"]
  defp send_placeholder(conn, svg) do
    # Safe: the SVG body is produced entirely by PlaceholderSvg which
    # escapes every interpolation. No user input reaches the body.
    conn
    |> put_resp_header("content-type", "image/svg+xml; charset=utf-8")
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("content-security-policy", "default-src 'none'")
    |> send_resp(200, svg)
  end

  # Refuse to proxy from instances we've explicitly suspended or
  # block-media'd. Other policies (silence, force_nsfw) are about
  # visibility, not the bytes themselves, so the proxy still serves
  # those — they're handled at the timeline + UI layer.
  defp check_instance_policy(url) do
    domain = URI.parse(url).host

    if is_binary(domain) do
      case Repo.get(InstancePolicy, String.downcase(domain)) do
        %InstancePolicy{policy: policy} when policy in @blocking_policies ->
          {:error, :instance_blocked}

        _ ->
          :ok
      end
    else
      :ok
    end
  end

  defp validate_remote_url(url) do
    uri = URI.parse(url)

    cond do
      uri.scheme not in ["http", "https"] ->
        {:error, :invalid_url}

      is_nil(uri.host) or uri.host == "" ->
        {:error, :invalid_url}

      private_host?(uri.host) ->
        {:error, :private_host}

      true ->
        :ok
    end
  end

  defp sanitize_content_type(content_type) when is_binary(content_type) do
    base = content_type |> String.split(";", parts: 2) |> hd() |> String.downcase()

    if Enum.any?(@safe_media_prefixes, &String.starts_with?(base, &1)) do
      base
    else
      "application/octet-stream"
    end
  end

  defp sanitize_content_type(_), do: "application/octet-stream"

  defp private_host?(host) do
    host in ["localhost", "127.0.0.1", "::1", "0.0.0.0"] or
      String.starts_with?(host, "10.") or
      String.starts_with?(host, "192.168.") or
      Regex.match?(~r/^172\.(1[6-9]|2[0-9]|3[01])\./, host)
  end
end
