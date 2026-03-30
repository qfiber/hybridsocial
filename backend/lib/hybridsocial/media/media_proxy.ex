defmodule Hybridsocial.Media.MediaProxy do
  @moduledoc """
  Proxies remote media URLs through the local server.

  Generates HMAC-signed URLs that point to the local media proxy endpoint,
  and verifies those signatures on incoming requests.
  """

  alias Hybridsocial.Config

  @doc "Check if media proxying is enabled."
  def enabled? do
    Config.get("media_proxy_enabled", false)
  end

  @doc """
  Convert a remote URL to a proxied URL with HMAC signature.
  Returns the original URL if media proxy is disabled or the URL is local.
  """
  def url(remote_url) when is_binary(remote_url) do
    if enabled?() and not local_url?(remote_url) do
      base = HybridsocialWeb.Endpoint.url()
      encoded = Base.url_encode64(remote_url, padding: false)
      signature = sign(encoded)
      "#{base}/proxy/media/#{signature}/#{encoded}"
    else
      remote_url
    end
  end

  def url(nil), do: nil

  @doc """
  Verify HMAC signature on a proxied URL.
  Returns {:ok, remote_url} or {:error, :invalid_signature}.
  """
  def verify_url(signature, encoded_url) do
    expected_sig = sign(encoded_url)

    if Plug.Crypto.secure_compare(expected_sig, signature) do
      case Base.url_decode64(encoded_url, padding: false) do
        {:ok, remote_url} -> {:ok, remote_url}
        :error -> {:error, :invalid_url}
      end
    else
      {:error, :invalid_signature}
    end
  end

  defp sign(data) do
    secret = secret_key()

    :crypto.mac(:hmac, :sha256, secret, data)
    |> Base.url_encode64(padding: false)
  end

  defp secret_key do
    Application.get_env(:hybridsocial, :secret_key_base, "default-secret-change-me")
  end

  defp local_url?(url) do
    local_host = URI.parse(HybridsocialWeb.Endpoint.url()).host
    remote_host = URI.parse(url).host
    local_host == remote_host
  end
end
