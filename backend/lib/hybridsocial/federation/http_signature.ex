defmodule Hybridsocial.Federation.HTTPSignature do
  @moduledoc """
  HTTP Signature signing and verification for ActivityPub federation.
  Implements draft-cavage-http-signatures with RSA-SHA256.
  """

  @signed_headers ["(request-target)", "host", "date", "digest"]

  @doc """
  Signs a request with the actor's private key.
  Returns a map of headers to add to the request.
  """
  def sign(request, private_key_pem, key_id) do
    date = Calendar.strftime(DateTime.utc_now(), "%a, %d %b %Y %H:%M:%S GMT")
    digest = build_digest(request[:body] || "")
    host = URI.parse(request[:url]).host

    request_data = %{
      "(request-target)" => "#{String.downcase(request[:method])} #{URI.parse(request[:url]).path}",
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
  Verifies an incoming request's HTTP signature.
  Returns {:ok, key_id} or {:error, reason}.
  """
  def verify(conn) do
    with {:ok, sig_params} <- parse_signature_header(conn),
         {:ok, public_key_pem} <- fetch_public_key(sig_params["keyId"]),
         {:ok, _} <- verify_signature(conn, sig_params, public_key_pem) do
      {:ok, sig_params["keyId"]}
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

  defp fetch_public_key(key_id) do
    actor_url = key_id |> String.split("#") |> List.first()

    uri = URI.parse(actor_url)
    host = uri.host || ""

    # Reject requests to private/internal hosts to prevent SSRF
    if private_host?(host) do
      {:error, :private_host}
    else
      headers = [
        {"Accept", "application/activity+json"}
      ]

      case HTTPoison.get(actor_url, headers,
             timeout: 5_000,
             recv_timeout: 5_000,
             max_body_length: 100_000
           ) do
        {:ok, %{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, %{"publicKey" => %{"publicKeyPem" => pem}}} ->
              {:ok, pem}

            _ ->
              {:error, :invalid_actor}
          end

        _ ->
          {:error, :fetch_failed}
      end
    end
  end

  defp private_host?(host) do
    host in ["localhost", "127.0.0.1", "::1", "0.0.0.0"] or
      String.starts_with?(host, "10.") or
      String.starts_with?(host, "192.168.") or
      Regex.match?(~r/^172\.(1[6-9]|2[0-9]|3[01])\./, host)
  end

  defp verify_signature(conn, sig_params, public_key_pem) do
    headers_to_verify = String.split(sig_params["headers"], " ")

    request_data =
      headers_to_verify
      |> Enum.map(fn
        "(request-target)" ->
          {"(request-target)", "#{String.downcase(to_string(conn.method))} #{conn.request_path}"}

        header ->
          value =
            conn
            |> Plug.Conn.get_req_header(header)
            |> List.first("")

          {header, value}
      end)
      |> Map.new()

    signing_string = build_signing_string(headers_to_verify, request_data)

    [pem_entry] = :public_key.pem_decode(public_key_pem)
    public_key = :public_key.pem_entry_decode(pem_entry)

    signature = Base.decode64!(sig_params["signature"])

    if :public_key.verify(signing_string, :sha256, signature, public_key) do
      {:ok, sig_params["keyId"]}
    else
      {:error, :invalid_signature}
    end
  end
end
