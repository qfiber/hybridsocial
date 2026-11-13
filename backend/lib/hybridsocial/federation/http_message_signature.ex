defmodule Hybridsocial.Federation.HTTPMessageSignature do
  @moduledoc """
  Inbound verification of RFC 9421 HTTP Message Signatures.

  Mastodon (4.7+) signs with the older draft-cavage scheme first and, when
  a server answers 400/401, re-sends the request signed per RFC 9421
  (`Signature-Input` + `Signature` + `Content-Digest`). Other servers may
  send RFC 9421 directly. This module parses those headers, rebuilds the
  signature base and checks it; key discovery and caching are shared with
  draft-cavage in `HTTPSignature`.

  What we require, mirroring Mastodon's own verifier:

    * `keyid` and `created` parameters; `created` no more than an hour in
      the future and no older than the draft-cavage Date window; an
      `expires`, when given, not passed (an hour's clock skew allowed)
    * `@method` covered, and the target: `@target-uri`, or `@authority`
      with `@path` or `@request-target`
    * on a POST, `content-digest` covered, so the body is bound to the
      signature (`DigestPlug` checks the digest against the body)
    * an RSA key: `alg` absent (inferred from the key), `rsa-v1_5-sha256`
      or `rsa-pss-sha512`. Other algorithms are refused.

  Derived components use our configured origin (`Endpoint.url/0`), not the
  request's Host header, so a request signed for another server can't be
  replayed to us.
  """

  @clock_skew_seconds 3600

  defstruct [:label, :components, :params, :raw_params, :signature, :key_id]

  @type t :: %__MODULE__{}

  @doc "Whether the request carries an RFC 9421 signature."
  def signed?(conn), do: Plug.Conn.get_req_header(conn, "signature-input") != []

  @doc """
  Parses the first signature present in both `Signature-Input` and
  `Signature` and checks the parameters and coverage we require.
  """
  def parse_and_check(conn, max_age_seconds) do
    with {:ok, sig} <- parse(conn),
         :ok <- check_time(sig.params, max_age_seconds),
         :ok <- check_coverage(conn, sig.components) do
      {:ok, sig}
    end
  end

  @doc "Verifies `sig` over `conn` against a public key PEM."
  def verify_with_pem(conn, %__MODULE__{} = sig, pem) do
    with {:ok, base} <- signature_base(conn, sig),
         {:ok, key} <- decode_rsa_public_key(pem),
         {:ok, verify} <- verifier(sig.params["alg"]) do
      if verify.(base, sig.signature, key),
        do: {:ok, sig.key_id},
        else: {:error, :invalid_signature}
    end
  end

  @doc """
  Checks an RFC 9530 `Content-Digest` header against `body`. At least one
  supported algorithm must be present, and every supported one must match.
  """
  def verify_content_digest(header, body) when is_binary(header) and is_binary(body) do
    supported =
      header
      |> parse_dictionary()
      |> Enum.flat_map(fn {alg, raw} ->
        with hash when not is_nil(hash) <- digest_hash(String.downcase(alg)),
             {:ok, bytes} <- parse_byte_sequence(raw) do
          [{hash, bytes}]
        else
          _ -> []
        end
      end)

    cond do
      supported == [] ->
        {:error, :unsupported_digest}

      Enum.all?(supported, fn {hash, bytes} ->
        Plug.Crypto.secure_compare(:crypto.hash(hash, body), bytes)
      end) ->
        :ok

      true ->
        {:error, :digest_mismatch}
    end
  end

  # ── Parsing ───────────────────────────────────────────────────────

  defp parse(conn) do
    with [input] <- header_values(conn, "signature-input"),
         [signature] <- header_values(conn, "signature"),
         inputs = parse_dictionary(input),
         signatures = Map.new(parse_dictionary(signature)),
         {label, raw_params} <-
           Enum.find(inputs, fn {label, _} -> Map.has_key?(signatures, label) end),
         {:ok, components, params} <- parse_inner_list(raw_params),
         {:ok, sig_bytes} <- parse_byte_sequence(signatures[label]),
         key_id when is_binary(key_id) and key_id != "" <- params["keyid"] do
      {:ok,
       %__MODULE__{
         label: label,
         components: components,
         params: params,
         raw_params: raw_params,
         signature: sig_bytes,
         key_id: key_id
       }}
    else
      _ -> {:error, :invalid_signature_input}
    end
  end

  # Multiple header lines are one comma-joined field.
  defp header_values(conn, name) do
    case Plug.Conn.get_req_header(conn, name) do
      [] -> []
      values -> [Enum.join(values, ", ")]
    end
  end

  # Splits an RFC 8941 dictionary into `[{key, raw_value}]`, keeping each
  # value's text verbatim: `@signature-params` must be rebuilt from exactly
  # what the signer serialized. Commas inside strings or inner lists don't
  # split.
  @doc false
  def parse_dictionary(field) do
    field
    |> split_top_level(?,)
    |> Enum.flat_map(fn member ->
      case String.split(String.trim(member), "=", parts: 2) do
        [key, value] when key != "" -> [{String.trim(key), String.trim(value)}]
        _ -> []
      end
    end)
  end

  defp split_top_level(str, sep) do
    {parts, current, _state} =
      str
      |> String.to_charlist()
      |> Enum.reduce({[], [], {false, 0}}, fn
        ?\\, {parts, cur, {true, depth}} -> {parts, [?\\ | cur], {:escape, depth}}
        ch, {parts, cur, {:escape, depth}} -> {parts, [ch | cur], {true, depth}}
        ?", {parts, cur, {in_str, depth}} -> {parts, [?" | cur], {not in_str, depth}}
        ?(, {parts, cur, {false, depth}} -> {parts, [?( | cur], {false, depth + 1}}
        ?), {parts, cur, {false, depth}} -> {parts, [?) | cur], {false, max(depth - 1, 0)}}
        ^sep, {parts, cur, {false, 0}} -> {[cur | parts], [], {false, 0}}
        ch, {parts, cur, state} -> {parts, [ch | cur], state}
      end)

    [current | parts]
    |> Enum.reverse()
    |> Enum.map(&(&1 |> Enum.reverse() |> List.to_string()))
  end

  # `("@method" "@target-uri" "content-digest");created=1;keyid="k"`
  defp parse_inner_list("(" <> rest) do
    case String.split(rest, ")", parts: 2) do
      [items, params] ->
        with {:ok, components} <- parse_component_items(items),
             {:ok, params} <- parse_params(params) do
          {:ok, components, params}
        end

      _ ->
        :error
    end
  end

  defp parse_inner_list(_), do: :error

  # Component items are strings; a component with parameters (`;sf`,
  # `;key`, `;req`, `;bs`) isn't supported and fails the parse.
  defp parse_component_items(items) do
    items
    |> String.split(" ", trim: true)
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case Regex.run(~r/\A"([^"\\]*)"\z/, item) do
        [_, name] -> {:cont, {:ok, [name | acc]}}
        _ -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, names} -> {:ok, Enum.reverse(names)}
      :error -> :error
    end
  end

  defp parse_params(""), do: {:ok, %{}}

  defp parse_params(";" <> params) do
    params
    |> split_top_level(?;)
    |> Enum.reduce_while({:ok, %{}}, fn param, {:ok, acc} ->
      case String.split(param, "=", parts: 2) do
        [key, value] ->
          case parse_bare_item(value) do
            {:ok, v} -> {:cont, {:ok, Map.put(acc, key, v)}}
            :error -> {:halt, :error}
          end

        [key] when key != "" ->
          {:cont, {:ok, Map.put(acc, key, true)}}

        _ ->
          {:halt, :error}
      end
    end)
  end

  defp parse_params(_), do: :error

  defp parse_bare_item(~s(") <> rest) do
    if String.ends_with?(rest, ~s(")),
      do: {:ok, rest |> String.slice(0..-2//1) |> unescape_sf_string()},
      else: :error
  end

  defp parse_bare_item(value) do
    case Integer.parse(value) do
      {int, ""} ->
        {:ok, int}

      _ ->
        if Regex.match?(~r/\A[A-Za-z*][A-Za-z0-9_.:\/%*+!#$&'^`|~-]*\z/, value),
          do: {:ok, value},
          else: :error
    end
  end

  # sf-string escapes are only \" and \\.
  defp unescape_sf_string(str) do
    str |> String.replace("\\\"", "\"") |> String.replace("\\\\", "\\")
  end

  defp parse_byte_sequence(":" <> rest) do
    with true <- String.ends_with?(rest, ":"),
         {:ok, bytes} <- rest |> String.slice(0..-2//1) |> Base.decode64() do
      {:ok, bytes}
    else
      _ -> :error
    end
  end

  defp parse_byte_sequence(_), do: :error

  # ── Requirements ──────────────────────────────────────────────────

  defp check_time(params, max_age_seconds) do
    now = System.os_time(:second)
    created = params["created"]
    expires = params["expires"]

    cond do
      not is_integer(created) -> {:error, :created_missing}
      created > now + @clock_skew_seconds -> {:error, :created_in_future}
      created < now - max_age_seconds -> {:error, :signature_too_old}
      is_integer(expires) and now > expires + @clock_skew_seconds -> {:error, :signature_expired}
      not is_nil(expires) and not is_integer(expires) -> {:error, :invalid_signature_input}
      true -> :ok
    end
  end

  defp check_coverage(conn, components) do
    covered = MapSet.new(components)

    targeted? =
      "@target-uri" in covered or
        ("@authority" in covered and ("@path" in covered or "@request-target" in covered))

    cond do
      "@method" not in covered or not targeted? -> {:error, :insufficient_coverage}
      conn.method == "POST" and "content-digest" not in covered -> {:error, :digest_not_signed}
      true -> :ok
    end
  end

  # ── Signature base (RFC 9421 §2.5) ────────────────────────────────

  defp signature_base(conn, sig) do
    sig.components
    |> Enum.reduce_while({:ok, []}, fn name, {:ok, lines} ->
      case component_value(conn, name) do
        {:ok, value} -> {:cont, {:ok, [~s("#{name}": #{value}) | lines]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, lines} ->
        {:ok, Enum.join(Enum.reverse([~s("@signature-params": #{sig.raw_params}) | lines]), "\n")}

      error ->
        error
    end
  end

  defp component_value(conn, "@method"), do: {:ok, conn.method}
  defp component_value(conn, "@target-uri"), do: {:ok, origin() <> request_target(conn)}
  defp component_value(_conn, "@authority"), do: {:ok, authority()}
  defp component_value(_conn, "@scheme"), do: {:ok, URI.parse(origin()).scheme}
  defp component_value(conn, "@path"), do: {:ok, conn.request_path}
  defp component_value(conn, "@query"), do: {:ok, "?" <> (conn.query_string || "")}
  defp component_value(conn, "@request-target"), do: {:ok, request_target(conn)}

  defp component_value(_conn, "@" <> _), do: {:error, :unsupported_component}

  defp component_value(conn, header) do
    case Plug.Conn.get_req_header(conn, String.downcase(header)) do
      [] -> {:error, :missing_component}
      values -> {:ok, values |> Enum.map(&String.trim/1) |> Enum.join(", ")}
    end
  end

  defp request_target(conn) do
    case conn.query_string do
      q when q in [nil, ""] -> conn.request_path
      q -> "#{conn.request_path}?#{q}"
    end
  end

  defp origin, do: HybridsocialWeb.Endpoint.url()

  defp authority do
    uri = URI.parse(origin())

    if uri.port in [nil, URI.default_port(uri.scheme)],
      do: String.downcase(uri.host),
      else: "#{String.downcase(uri.host)}:#{uri.port}"
  end

  # ── Crypto ────────────────────────────────────────────────────────

  defp verifier(alg) when alg in [nil, "rsa-v1_5-sha256"],
    do: {:ok, fn base, sig, key -> :public_key.verify(base, :sha256, sig, key) end}

  defp verifier("rsa-pss-sha512") do
    {:ok,
     fn base, sig, key ->
       :public_key.verify(base, :sha512, sig, key,
         rsa_padding: :rsa_pkcs1_pss_padding,
         rsa_pss_saltlen: 64,
         rsa_mgf1_md: :sha512
       )
     end}
  end

  defp verifier(_), do: {:error, :unsupported_algorithm}

  defp decode_rsa_public_key(pem) do
    case :public_key.pem_decode(pem) do
      [entry] ->
        case :public_key.pem_entry_decode(entry) do
          {:RSAPublicKey, _, _} = key -> {:ok, key}
          _ -> {:error, :unsupported_key}
        end

      _ ->
        {:error, :invalid_key}
    end
  rescue
    _ -> {:error, :invalid_key}
  end

  defp digest_hash("sha-256"), do: :sha256
  defp digest_hash("sha-512"), do: :sha512
  defp digest_hash(_), do: nil
end
