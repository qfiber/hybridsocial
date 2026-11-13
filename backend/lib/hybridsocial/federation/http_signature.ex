defmodule Hybridsocial.Federation.HTTPSignature do
  @moduledoc """
  HTTP Signature signing and verification for ActivityPub federation.
  Implements draft-cavage-http-signatures with RSA-SHA256.
  """

  @signed_headers ["(request-target)", "host", "date", "digest"]
  # GETs have no body, so no Digest. Mastodon's "secure mode" / authorized-fetch
  # gates actor + object dereferences behind a signed GET — without it, those
  # instances return 401 to our profile/object lookups.
  @signed_headers_get ["(request-target)", "host", "date"]

  # Per draft-cavage-http-signatures + Mastodon convention, signed
  # requests must be reasonably fresh. Mastodon rejects with > 12h
  # skew either way; we mirror that.
  @signature_max_skew_seconds 12 * 3600

  @doc """
  Signs a request with the actor's private key.
  Returns a map of headers to add to the request.
  """
  def sign(request, private_key_pem, key_id) do
    date = Calendar.strftime(DateTime.utc_now(), "%a, %d %b %Y %H:%M:%S GMT")
    digest = build_digest(request[:body] || "")
    host = URI.parse(request[:url]).host

    request_data = %{
      "(request-target)" =>
        "#{String.downcase(request[:method])} #{request_target_path(request[:url])}",
      "host" => host,
      "date" => date,
      "digest" => digest
    }

    signing_string = build_signing_string(@signed_headers, request_data)
    signature = create_signature(signing_string, private_key_pem)

    header_value =
      ~s(keyId="#{key_id}",algorithm="rsa-sha256",headers="#{Enum.join(@signed_headers, " ")}",signature="#{signature}")

    %{
      "Signature" => header_value,
      "Date" => date,
      "Digest" => digest,
      "Host" => host
    }
  end

  @doc """
  Signs a GET request (no body, no Digest header) with the given private
  key. Use for "authorized-fetch" — many Mastodon instances require it
  for actor + object dereferences. Returns the headers to attach to the
  outbound Req.get call.
  """
  def sign_get(url, private_key_pem, key_id) do
    date = Calendar.strftime(DateTime.utc_now(), "%a, %d %b %Y %H:%M:%S GMT")
    host = URI.parse(url).host

    request_data = %{
      "(request-target)" => "get #{request_target_path(url)}",
      "host" => host,
      "date" => date
    }

    signing_string = build_signing_string(@signed_headers_get, request_data)
    signature = create_signature(signing_string, private_key_pem)

    header_value =
      ~s(keyId="#{key_id}",algorithm="rsa-sha256",headers="#{Enum.join(@signed_headers_get, " ")}",signature="#{signature}")

    %{
      "Signature" => header_value,
      "Date" => date,
      "Host" => host
    }
  end

  # Mastodon and friends sign the path including the query string. URI.parse
  # gives us .path without the query, so reassemble. Empty paths must become
  # "/" — some peers reject "(request-target): get " with no path.
  defp request_target_path(url) do
    uri = URI.parse(url)
    path = uri.path || "/"

    case uri.query do
      nil -> path
      "" -> path
      q -> "#{path}?#{q}"
    end
  end

  @doc """
  Verifies an incoming request's HTTP signature.
  Returns {:ok, key_id} or {:error, reason}.
  """
  def verify(conn) do
    with {:ok, sig_params} <- parse_signature_header(conn),
         {:ok, key_id} <- fetch_key_id(sig_params),
         :ok <- verify_date_freshness(conn),
         {:ok, _} <- verify_with_key(conn, sig_params, key_id) do
      {:ok, key_id}
    end
  end

  defp fetch_key_id(%{"keyId" => key_id}) when is_binary(key_id) and key_id != "",
    do: {:ok, key_id}

  defp fetch_key_id(_), do: {:error, :missing_key_id}

  # Verify against the cached key first; on a miss, or if the cached key no
  # longer verifies (the actor rotated it), fetch the current key once and
  # try again. A forged signature costs at most one fetch per keyId per
  # cache window, never one per request.
  defp verify_with_key(conn, sig_params, key_id) do
    case cached_public_key(key_id) do
      nil ->
        with {:ok, pem} <- fetch_and_cache_public_key(key_id) do
          verify_signature(conn, sig_params, pem)
        end

      cached_pem ->
        case verify_signature(conn, sig_params, cached_pem) do
          {:ok, _} = ok ->
            ok

          {:error, :invalid_signature} ->
            with {:ok, pem} when pem != cached_pem <- fetch_and_cache_public_key(key_id) do
              verify_signature(conn, sig_params, pem)
            else
              {:ok, _same_pem} -> {:error, :invalid_signature}
              error -> error
            end

          error ->
            error
        end
    end
  end

  # Date-header freshness gate. Closes the unbounded replay-attack
  # window — without this, an intercepted signed request would be
  # accepted forever. Returns :ok within ±12h of now, otherwise
  # `{:error, :date_invalid | :date_too_old | :date_too_skewed}`.
  defp verify_date_freshness(conn) do
    case Plug.Conn.get_req_header(conn, "date") do
      [date_str | _] ->
        case parse_http_date(date_str) do
          {:ok, sent_at} ->
            skew = DateTime.diff(DateTime.utc_now(), sent_at, :second)

            cond do
              skew > @signature_max_skew_seconds -> {:error, :date_too_old}
              skew < -@signature_max_skew_seconds -> {:error, :date_too_skewed}
              true -> :ok
            end

          :error ->
            {:error, :date_invalid}
        end

      [] ->
        {:error, :date_missing}
    end
  end

  # RFC 7231 IMF-fixdate format: "Sun, 06 Nov 1994 08:49:37 GMT".
  # The `Calendar.strftime` we use to SIGN matches this exactly. We
  # also accept ISO-8601 as a fallback in case a peer signs with that
  # format (some implementations do).
  defp parse_http_date(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> {:ok, dt}
      _ -> parse_imf_fixdate(str)
    end
  end

  defp parse_imf_fixdate(str) do
    months = %{
      "Jan" => 1,
      "Feb" => 2,
      "Mar" => 3,
      "Apr" => 4,
      "May" => 5,
      "Jun" => 6,
      "Jul" => 7,
      "Aug" => 8,
      "Sep" => 9,
      "Oct" => 10,
      "Nov" => 11,
      "Dec" => 12
    }

    with [_dow, day, mon, year, time, _tz] <- String.split(str, ~r/[\s,]+/, trim: true),
         month when is_integer(month) <- months[mon],
         {day_n, ""} <- Integer.parse(day),
         {year_n, ""} <- Integer.parse(year),
         [h, m, s] <- String.split(time, ":"),
         {h_n, ""} <- Integer.parse(h),
         {m_n, ""} <- Integer.parse(m),
         {s_n, ""} <- Integer.parse(s),
         {:ok, naive} <- NaiveDateTime.new(year_n, month, day_n, h_n, m_n, s_n) do
      {:ok, DateTime.from_naive!(naive, "Etc/UTC")}
    else
      _ -> :error
    end
  end

  @doc """
  Constructs the string to sign from headers and request data.
  """
  def build_signing_string(headers_to_sign, request_data) do
    headers_to_sign
    |> Enum.map(fn header -> "#{header}: #{request_data[header]}" end)
    |> Enum.join("\n")
  end

  # --- Private helpers ---

  defp build_digest(body) do
    hash = :crypto.hash(:sha256, body)
    "SHA-256=#{Base.encode64(hash)}"
  end

  defp create_signature(signing_string, private_key_pem) do
    [pem_entry] = :public_key.pem_decode(private_key_pem)
    private_key = :public_key.pem_entry_decode(pem_entry)

    signing_string
    |> :public_key.sign(:sha256, private_key)
    |> Base.encode64()
  end

  defp parse_signature_header(conn) do
    case Plug.Conn.get_req_header(conn, "signature") do
      [sig_header] ->
        params =
          sig_header
          |> String.split(",")
          |> Enum.map(fn part ->
            [key, value] = String.split(part, "=", parts: 2)
            {String.trim(key), String.trim(value, "\"")}
          end)
          |> Map.new()

        {:ok, params}

      _ ->
        {:error, :missing_signature}
    end
  end

  @key_cache_prefix "httpsig:key:"

  defp cached_public_key(key_id) do
    case Hybridsocial.Cache.get(@key_cache_prefix <> key_id) do
      pem when is_binary(pem) -> pem
      _ -> nil
    end
  end

  defp fetch_and_cache_public_key(key_id) do
    with {:ok, pem} <- fetch_public_key(key_id) do
      Hybridsocial.Cache.set(@key_cache_prefix <> key_id, pem, key_cache_ttl())
      {:ok, pem}
    end
  end

  defp key_cache_ttl do
    case Hybridsocial.Config.get("federation_key_cache_seconds", 3600) do
      n when is_integer(n) and n > 0 -> n
      _ -> 3600
    end
  end

  # Signed with the instance actor (`SignedFetch`). Mastodon's secure mode
  # (authorized fetch), now on at mastodon.social and many others, answers
  # 401 to an unsigned actor fetch, and an unsigned key lookup meant we could
  # never verify, and so 401'd, every delivery from those servers. There's
  # no verification loop: the peer verifies our GET by fetching our instance
  # actor, which is served to anyone without a signature.
  defp fetch_public_key(key_id) do
    actor_url = key_id |> String.split("#") |> List.first()
    host = URI.parse(actor_url).host || ""

    # Reject requests to private/internal hosts to prevent SSRF
    if private_host?(host) do
      {:error, :private_host}
    else
      opts =
        [timeout: 5_000, recv_timeout: 5_000, max_body_length: 100_000] ++
          Application.get_env(:hybridsocial, :http_signature_fetch_options, [])

      case Hybridsocial.Federation.SignedFetch.get(actor_url, opts) do
        {:ok, %{status_code: 200, body: body}} -> extract_public_key(body, key_id)
        _ -> {:error, :fetch_failed}
      end
    end
  end

  # The key must be the one the signature names: `publicKey.id == keyId`.
  # Otherwise any key published under an actor URL could stand in for a
  # different keyId. Some servers publish a list of keys.
  defp extract_public_key(body, key_id) do
    with {:ok, %{"publicKey" => keys}} <- Jason.decode(body),
         %{"publicKeyPem" => pem} when is_binary(pem) <-
           keys |> List.wrap() |> Enum.find(&match?(%{"id" => ^key_id}, &1)) do
      {:ok, pem}
    else
      _ -> {:error, :invalid_actor}
    end
  end

  defp private_host?(host) do
    host in ["localhost", "127.0.0.1", "::1", "0.0.0.0"] or
      String.starts_with?(host, "10.") or
      String.starts_with?(host, "192.168.") or
      Regex.match?(~r/^172\.(1[6-9]|2[0-9]|3[01])\./, host)
  end

  defp verify_signature(conn, sig_params, public_key_pem) do
    # draft-cavage: an absent `headers` parameter means just "date".
    headers_to_verify = String.split(sig_params["headers"] || "date", " ", trim: true)

    if conn.method == "POST" and "digest" not in headers_to_verify do
      # DigestPlug checks the body against the Digest header, but unless that
      # header is itself signed, a captured signature could be replayed with
      # another body. Every major implementation signs it on POST.
      {:error, :digest_not_signed}
    else
      do_verify_signature(conn, sig_params, headers_to_verify, public_key_pem)
    end
  end

  defp do_verify_signature(conn, sig_params, headers_to_verify, public_key_pem) do
    request_data =
      headers_to_verify
      |> Enum.map(fn
        "(request-target)" ->
          # Match what the signer put into (request-target): the path with
          # query string preserved. Phoenix exposes them separately so we
          # rejoin here. Inbox POSTs never carry queries, but signed GETs
          # against /actors/:id/outbox?page=1 etc. do.
          target_path =
            case conn.query_string do
              "" -> conn.request_path
              nil -> conn.request_path
              q -> "#{conn.request_path}?#{q}"
            end

          {"(request-target)", "#{String.downcase(to_string(conn.method))} #{target_path}"}

        header ->
          value =
            conn
            |> Plug.Conn.get_req_header(header)
            |> List.first("")

          {header, value}
      end)
      |> Map.new()

    signing_string = build_signing_string(headers_to_verify, request_data)

    # Malformed input from a peer is a rejection, not a crash.
    with {:ok, public_key} <- decode_public_key(public_key_pem),
         {:ok, signature} <- Base.decode64(sig_params["signature"] || "") do
      if :public_key.verify(signing_string, :sha256, signature, public_key) do
        {:ok, sig_params["keyId"]}
      else
        {:error, :invalid_signature}
      end
    else
      :error -> {:error, :invalid_signature}
      {:error, _} = error -> error
    end
  end

  defp decode_public_key(pem) do
    case :public_key.pem_decode(pem) do
      [entry] -> {:ok, :public_key.pem_entry_decode(entry)}
      _ -> {:error, :invalid_key}
    end
  rescue
    _ -> {:error, :invalid_key}
  end
end
