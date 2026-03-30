defmodule HybridsocialWeb.Plugs.DigestPlug do
  @moduledoc """
  Validates the Digest header on incoming POST requests to inbox endpoints.

  Computes SHA-256 of the request body and compares it against the provided
  Digest header. Rejects with 401 on mismatch.
  """
  import Plug.Conn

  require Logger

  def init(opts), do: opts

  def call(%{method: "POST"} = conn, _opts) do
    case get_req_header(conn, "digest") do
      [digest_header] ->
        verify_digest(conn, digest_header)

      [] ->
        # No digest header — allow through (some implementations omit it)
        conn
    end
  end

  def call(conn, _opts), do: conn

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
