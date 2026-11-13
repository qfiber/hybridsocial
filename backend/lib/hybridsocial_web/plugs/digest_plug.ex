defmodule HybridsocialWeb.Plugs.DigestPlug do
  @moduledoc """
  Validates the Digest header on incoming POST requests to inbox endpoints.

  Computes SHA-256 of the request body and compares it against the provided
  Digest header. Rejects with 401 on mismatch — and on absence, because
  allowing missing-Digest POSTs lets an attacker replay a captured
  Signature with a tampered body whenever the signed-headers list happens
  to omit "digest" (which the verifier honors as-is). Every modern
  fediverse server sends Digest on inbox POSTs; refusing without it closes
  the body-tampering window without breaking real peers.
  """
  import Plug.Conn

  alias Hybridsocial.Federation.HTTPMessageSignature

  require Logger

  def init(opts), do: opts

  def call(%{method: "POST"} = conn, _opts) do
    case {get_req_header(conn, "digest"), get_req_header(conn, "content-digest")} do
      {[digest_header], _} ->
        verify_digest(conn, digest_header)

      # RFC 9421 senders use RFC 9530 Content-Digest instead. The signature
      # must cover it (HTTPMessageSignature requires that on POST).
      {[], [_ | _] = content_digest} ->
        verify_content_digest(conn, Enum.join(content_digest, ", "))

      {[], []} ->
        if signature_check_enabled?() do
          Logger.warning(
            "Inbox POST missing Digest header (#{conn.request_path}) " <>
              missing_digest_context(conn)
          )

          conn
          |> put_status(401)
          |> Phoenix.Controller.json(%{error: "Digest header required"})
          |> halt()
        else
          # Test/dev mode where signature verification is disabled.
          # Strictness is paired with the signature gate so the same
          # switch toggles both: production enforces, fixtures pass.
          conn
        end
    end
  end

  def call(conn, _opts), do: conn

  # Who sent a Digest-less POST and how it was signed, so a peer that signs
  # with RFC 9421 (`Signature-Input` + `Content-Digest`) can be told apart
  # from junk. Only the key's host is logged; keyIds are public anyway.
  defp missing_digest_context(conn) do
    host =
      [get_req_header(conn, "signature"), get_req_header(conn, "signature-input")]
      |> List.flatten()
      |> Enum.find_value("unknown", fn header ->
        case Regex.run(~r/keyid="([^"]+)"/i, header) do
          [_, key_id] -> URI.parse(key_id).host
          _ -> nil
        end
      end)

    "from=#{host} content_digest=#{header?(conn, "content-digest")} " <>
      "signature_input=#{header?(conn, "signature-input")} " <>
      "signature=#{header?(conn, "signature")}"
  end

  defp header?(conn, name), do: get_req_header(conn, name) != []

  defp signature_check_enabled? do
    Application.get_env(:hybridsocial, :federation_signature_check, true)
  end

  defp verify_content_digest(conn, header) do
    case HTTPMessageSignature.verify_content_digest(header, read_cached_body(conn)) do
      :ok ->
        conn

      {:error, reason} ->
        Logger.warning("Content-Digest rejected: #{reason}")

        conn
        |> put_status(401)
        |> Phoenix.Controller.json(%{error: "Invalid digest"})
        |> halt()
    end
  end

  defp verify_digest(conn, digest_header) do
    # Read the raw body — it should already be cached by Plug.Parsers
    body = read_cached_body(conn)

    expected = "SHA-256=" <> Base.encode64(:crypto.hash(:sha256, body))

    if Plug.Crypto.secure_compare(expected, digest_header) do
      conn
    else
      Logger.warning("Digest mismatch: expected #{expected}, got #{digest_header}")

      conn
      |> put_status(401)
      |> Phoenix.Controller.json(%{error: "Invalid digest"})
      |> halt()
    end
  end

  defp read_cached_body(conn) do
    # The body should be available via conn.assigns or cached body reader
    case conn.assigns[:raw_body] do
      body when is_binary(body) ->
        body

      [body | _] when is_binary(body) ->
        body

      _ ->
        # Fallback: re-encode params as JSON (less accurate but functional)
        case Jason.encode(conn.params) do
          {:ok, json} -> json
          _ -> ""
        end
    end
  end
end
