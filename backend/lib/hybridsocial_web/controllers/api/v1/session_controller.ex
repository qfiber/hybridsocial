defmodule HybridsocialWeb.Api.V1.SessionController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Auth

  def index(conn, _params) do
    identity_id = conn.assigns.current_identity.id
    current_token_hash = Auth.Token.hash_token(conn.assigns.current_token)
    sessions = Auth.list_sessions(identity_id)

    # Sort: current session first, then by most recent activity
    sorted =
      Enum.sort_by(sessions, fn session ->
        is_current = session.token_hash == current_token_hash
        # Current session gets priority (sort key 0), others by last_active_at descending
        {if(is_current, do: 0, else: 1), -(to_unix(session.last_active_at) || 0)}
      end)

    json(conn, %{
      data:
        Enum.map(sorted, fn session ->
          serialize(session, session.token_hash == current_token_hash)
        end)
    })
  end

  def delete(conn, %{"id" => id}) do
    identity_id = conn.assigns.current_identity.id

    case Auth.revoke_session(identity_id, id) do
      {:ok, _} ->
        json(conn, %{message: "session.revoked"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "session.not_found"})
    end
  end

  def delete_others(conn, _params) do
    identity_id = conn.assigns.current_identity.id
    current_token = conn.assigns.current_token

    {:ok, count} = Auth.revoke_other_sessions(identity_id, current_token)

    json(conn, %{message: "sessions.revoked", count: count})
  end

  defp serialize(session, is_current) do
    %{
      id: session.id,
      device_name: session.device_name || infer_device_name(session),
      ip_address: mask_ip(session.ip_address),
      location: geolocate_ip(session.ip_address),
      user_agent: session.user_agent,
      last_active_at: session.last_active_at || session.inserted_at,
      created_at: session.inserted_at,
      current: is_current
    }
  end

  # If device_name is missing, try to infer from user_agent or show creation time
  defp infer_device_name(%{user_agent: ua}) when is_binary(ua) and byte_size(ua) > 0 do
    Auth.parse_device_name(ua)
  end

  defp infer_device_name(%{inserted_at: created}) when not is_nil(created) do
    "Session from #{Calendar.strftime(created, "%b %d, %Y")}"
  end

  defp infer_device_name(_), do: "Unknown device"

  # Mask last octet for privacy
  defp mask_ip(nil), do: nil

  defp mask_ip(ip) do
    case String.split(ip, ".") do
      [a, b, c, _d] -> "#{a}.#{b}.#{c}.***"
      _ -> ip
    end
  end

  # Simple IP geolocation using ip-api.com (free, no key needed, 45 req/min)
  # Returns nil for localhost/private IPs
  defp geolocate_ip(nil), do: nil
  defp geolocate_ip("127." <> _), do: "Local"
  defp geolocate_ip("10." <> _), do: "Private network"
  defp geolocate_ip("192.168." <> _), do: "Private network"
  defp geolocate_ip("172." <> rest) do
    case Integer.parse(rest) do
      {n, _} when n >= 16 and n <= 31 -> "Private network"
      _ -> lookup_ip_location("172." <> rest)
    end
  end

  defp geolocate_ip(ip), do: lookup_ip_location(ip)

  defp lookup_ip_location(ip) do
    # Check cache first
    cache_key = "geo:#{ip}"

    case Hybridsocial.Cache.get(cache_key) do
      nil ->
        # Fetch from ip-api.com (free tier, http only)
        result =
          try do
            case HTTPoison.get("http://ip-api.com/json/#{ip}?fields=status,country,city",
                   [],
                   recv_timeout: 3_000,
                   timeout: 3_000
                 ) do
              {:ok, %{status_code: 200, body: body}} ->
                case Jason.decode(body) do
                  {:ok, %{"status" => "success", "city" => city, "country" => country}} ->
                    "#{city}, #{country}"

                  _ ->
                    nil
                end

              _ ->
                nil
            end
          rescue
            _ -> nil
          end

        # Cache for 24 hours (IPs rarely change location)
        if result, do: Hybridsocial.Cache.set(cache_key, result, 86_400)
        result

      cached ->
        cached
    end
  end

  defp to_unix(nil), do: nil
  defp to_unix(%DateTime{} = dt), do: DateTime.to_unix(dt)
end
