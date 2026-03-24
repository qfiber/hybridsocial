defmodule Hybridsocial.Security.UrlValidator do
  @moduledoc """
  Validates URLs to prevent SSRF attacks.
  Blocks private IPs, localhost, and non-HTTP schemes.
  """
  import Bitwise

  @private_ranges [
    # 10.0.0.0/8
    {10, 0, 0, 0, 8},
    # 172.16.0.0/12
    {172, 16, 0, 0, 12},
    # 192.168.0.0/16
    {192, 168, 0, 0, 16},
    # 127.0.0.0/8 (loopback)
    {127, 0, 0, 0, 8},
    # 169.254.0.0/16 (link-local / cloud metadata)
    {169, 254, 0, 0, 16},
    # 0.0.0.0/8
    {0, 0, 0, 0, 8}
  ]

  @blocked_hosts ["localhost", "localhost.localdomain", "[::1]", "metadata.google.internal"]

  @doc """
  Validates a URL is safe for server-side fetching.
  Returns :ok or {:error, reason}.
  """
  def validate(url) when is_binary(url) do
    uri = URI.parse(url)

    with :ok <- validate_scheme(uri),
         :ok <- validate_host(uri),
         :ok <- validate_port(uri),
         :ok <- validate_not_private(uri.host) do
      :ok
    end
  end

  def validate(_), do: {:error, :invalid_url}

  @doc "Validates a domain string (not a full URL)."
  def validate_domain(domain) when is_binary(domain) do
    validate("https://#{domain}/")
  end

  def validate_domain(_), do: {:error, :invalid_domain}

  defp validate_scheme(%URI{scheme: scheme}) when scheme in ["http", "https"], do: :ok
  defp validate_scheme(_), do: {:error, :invalid_scheme}

  defp validate_host(%URI{host: nil}), do: {:error, :no_host}
  defp validate_host(%URI{host: ""}), do: {:error, :no_host}

  defp validate_host(%URI{host: host}) do
    if String.downcase(host) in @blocked_hosts do
      {:error, :blocked_host}
    else
      :ok
    end
  end

  defp validate_port(%URI{port: nil}), do: :ok
  defp validate_port(%URI{port: 80}), do: :ok
  defp validate_port(%URI{port: 443}), do: :ok
  defp validate_port(%URI{port: port}) when port > 0 and port < 65536, do: :ok
  defp validate_port(_), do: {:error, :invalid_port}

  defp validate_not_private(host) do
    case resolve_to_ip(host) do
      {:ok, ip_tuple} ->
        if private_ip?(ip_tuple) do
          {:error, :private_ip}
        else
          :ok
        end

      {:error, _} ->
        # DNS resolution failed — fail closed (don't allow)
        {:error, :dns_resolution_failed}
    end
  end

  defp resolve_to_ip(host) do
    # Check if it's already an IP
    case :inet.parse_address(to_charlist(host)) do
      {:ok, ip} ->
        {:ok, ip}

      {:error, _} ->
        # Try DNS resolution
        case :inet.getaddr(to_charlist(host), :inet) do
          {:ok, ip} -> {:ok, ip}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp private_ip?(ip_tuple) when is_tuple(ip_tuple) do
    Enum.any?(@private_ranges, fn {a, b, c, d, prefix_len} ->
      ip_in_range?(ip_tuple, {a, b, c, d}, prefix_len)
    end)
  end

  defp ip_in_range?({a1, b1, c1, d1}, {a2, b2, c2, d2}, prefix_len) do
    ip_int = a1 * 16_777_216 + b1 * 65_536 + c1 * 256 + d1
    net_int = a2 * 16_777_216 + b2 * 65_536 + c2 * 256 + d2
    mask = 0xFFFFFFFF <<< (32 - prefix_len) &&& 0xFFFFFFFF
    (ip_int &&& mask) == (net_int &&& mask)
  end
end
