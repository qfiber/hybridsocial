defmodule Hybridsocial.Push.WebPush do
  @moduledoc """
  Web Push notification sending with VAPID authentication.
  Uses RFC 8291 (aes128gcm) content encoding and RFC 8292 (VAPID) auth.
  Built on top of :crypto, JOSE (already a dep via Joken), and HTTPoison.
  """

  @doc """
  Send a web push notification.

  - `payload` - the string body to encrypt and send
  - `subscription` - map with `:endpoint` and `:keys` (`:p256dh`, `:auth`)
  - `vapid` - map with `:subject`, `:public_key`, `:private_key` (all URL-safe base64)
  """
  def send_web_push(payload, subscription, vapid) do
    with {:ok, encrypted_body, content_encoding_headers} <-
           encrypt(payload, subscription.keys.p256dh, subscription.keys.auth),
         {:ok, vapid_headers} <- vapid_headers(subscription.endpoint, vapid) do
      headers =
        Map.merge(content_encoding_headers, vapid_headers)
        |> Map.put("Content-Type", "application/octet-stream")
        |> Map.put("TTL", "86400")
        |> Map.to_list()

      HTTPoison.post(subscription.endpoint, encrypted_body, headers, recv_timeout: 15_000)
    end
  end

  # --- VAPID ---

  defp vapid_headers(endpoint, vapid) do
    uri = URI.parse(endpoint)
    audience = "#{uri.scheme}://#{uri.host}"

    now = System.system_time(:second)

    claims = %{
      "aud" => audience,
      "exp" => now + 12 * 3600,
      "sub" => vapid.subject
    }

    # Decode the raw private key bytes
    private_key_bytes = Base.url_decode64!(vapid.private_key, padding: false)
    public_key_bytes = Base.url_decode64!(vapid.public_key, padding: false)

    # Build a JWK for ES256
    # The private key is the raw 32-byte scalar, public key is the 65-byte uncompressed point
    jwk = jose_ec_key(private_key_bytes, public_key_bytes)

    {_, token} = JOSE.JWT.sign(jwk, %{"alg" => "ES256"}, claims) |> JOSE.JWS.compact()

    headers = %{
      "Authorization" => "vapid t=#{token}, k=#{vapid.public_key}",
      "Urgency" => "normal",
      "Topic" => "notification"
    }

    {:ok, headers}
  end

  defp jose_ec_key(private_bytes, public_bytes) do
    # For P-256: private key is 32 bytes, public key is 65 bytes (04 || x || y)
    <<_prefix::8, x::binary-size(32), y::binary-size(32)>> = public_bytes

    %{
      "kty" => "EC",
      "crv" => "P-256",
      "x" => Base.url_encode64(x, padding: false),
      "y" => Base.url_encode64(y, padding: false),
      "d" => Base.url_encode64(private_bytes, padding: false)
    }
    |> JOSE.JWK.from_map()
  end

  # --- Encryption (RFC 8291 aes128gcm) ---

  defp encrypt(payload, p256dh_b64, auth_b64) do
    # Decode subscriber keys
    client_public = Base.url_decode64!(p256dh_b64, padding: false)
    auth_secret = Base.url_decode64!(auth_b64, padding: false)

    # Generate ephemeral ECDH key pair
    {server_public, server_private} = :crypto.generate_key(:ecdh, :prime256v1)

    # ECDH shared secret
    shared_secret = :crypto.compute_key(:ecdh, client_public, server_private, :prime256v1)

    # Generate salt
    salt = :crypto.strong_rand_bytes(16)

    # Derive keys using HKDF (RFC 8291 Section 3.4)
    # IKM = HKDF(auth_secret, shared_secret, "WebPush: info" || 0x00 || client_public || server_public, 32)
    info_header = "WebPush: info\0"
    key_info = info_header <> client_public <> server_public

    # PRK from auth
    prk_auth = hkdf_extract(auth_secret, shared_secret)
    ikm = hkdf_expand(prk_auth, key_info, 32)

    # Content encryption key
    cek_info = "Content-Encoding: aes128gcm\0"
    prk = hkdf_extract(salt, ikm)
    cek = hkdf_expand(prk, cek_info, 16)

    # Nonce
    nonce_info = "Content-Encoding: nonce\0"
    nonce = hkdf_expand(prk, nonce_info, 12)

    # Pad the payload (add delimiter byte 0x02 for final record)
    padded = payload <> <<2>>

    # Encrypt with AES-128-GCM
    {ciphertext, tag} = :crypto.crypto_one_time_aead(:aes_128_gcm, cek, nonce, padded, "", true)

    # Build the aes128gcm body:
    # salt (16) || rs (4, big-endian uint32) || idlen (1) || keyid (65) || ciphertext || tag
    rs = byte_size(padded) + 16 + 1
    record_size = <<rs::unsigned-big-integer-size(32)>>
    id_len = <<byte_size(server_public)::8>>

    body = salt <> record_size <> id_len <> server_public <> ciphertext <> tag

    headers = %{
      "Content-Encoding" => "aes128gcm"
    }

    {:ok, body, headers}
  end

  # HKDF-Extract (RFC 5869)
  defp hkdf_extract(salt, ikm) do
    :crypto.mac(:hmac, :sha256, salt, ikm)
  end

  # HKDF-Expand (RFC 5869)
  defp hkdf_expand(prk, info, length) do
    # For length <= 32 (SHA-256 output), only one iteration needed
    t1 = :crypto.mac(:hmac, :sha256, prk, info <> <<1>>)
    binary_part(t1, 0, length)
  end
end
