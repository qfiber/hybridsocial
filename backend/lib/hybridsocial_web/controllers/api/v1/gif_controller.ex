defmodule HybridsocialWeb.Api.V1.GifController do
  use HybridsocialWeb, :controller

  @giphy_trending_url "https://api.giphy.com/v1/gifs/trending"
  @giphy_search_url "https://api.giphy.com/v1/gifs/search"
  @default_limit 20

  # GET /api/v1/gifs/trending
  def trending(conn, _params) do
    case api_key() do
      "" ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "gif_service_unavailable", error_description: "GIF service is not configured"})

      key ->
        url = "#{@giphy_trending_url}?api_key=#{URI.encode_www_form(key)}&limit=#{@default_limit}&rating=pg-13"

        case HTTPoison.get(url, [], recv_timeout: 10_000, timeout: 10_000) do
          {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
            gifs = body |> Jason.decode!() |> Map.get("data", []) |> Enum.map(&serialize_gif/1)
            json(conn, gifs)

          {:ok, %HTTPoison.Response{status_code: status}} ->
            conn
            |> put_status(:bad_gateway)
            |> json(%{error: "giphy_error", error_description: "GIPHY returned status #{status}"})

          {:error, _reason} ->
            conn
            |> put_status(:bad_gateway)
            |> json(%{error: "giphy_error", error_description: "Failed to reach GIPHY"})
        end
    end
  end

  # GET /api/v1/gifs/search?q=QUERY
  def search(conn, params) do
    query = Map.get(params, "q", "")

    if String.trim(query) == "" do
      json(conn, [])
    else
      case api_key() do
        "" ->
          conn
          |> put_status(:service_unavailable)
          |> json(%{error: "gif_service_unavailable", error_description: "GIF service is not configured"})

        key ->
          url =
            "#{@giphy_search_url}?api_key=#{URI.encode_www_form(key)}&q=#{URI.encode_www_form(query)}&limit=#{@default_limit}&rating=pg-13"

          case HTTPoison.get(url, [], recv_timeout: 10_000, timeout: 10_000) do
            {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
              gifs = body |> Jason.decode!() |> Map.get("data", []) |> Enum.map(&serialize_gif/1)
              json(conn, gifs)

            {:ok, %HTTPoison.Response{status_code: status}} ->
              conn
              |> put_status(:bad_gateway)
              |> json(%{error: "giphy_error", error_description: "GIPHY returned status #{status}"})

            {:error, _reason} ->
              conn
              |> put_status(:bad_gateway)
              |> json(%{error: "giphy_error", error_description: "Failed to reach GIPHY"})
          end
      end
    end
  end

  defp api_key do
    Hybridsocial.Config.get("giphy_api_key", "")
  end

  defp serialize_gif(gif) do
    fixed = get_in(gif, ["images", "fixed_height"]) || %{}
    still = get_in(gif, ["images", "fixed_height_still"]) || %{}
    original = get_in(gif, ["images", "original"]) || %{}

    %{
      id: gif["id"],
      title: gif["title"] || "",
      url: original["url"] || fixed["url"] || "",
      preview_url: still["url"] || "",
      width: parse_dimension(fixed["width"]),
      height: parse_dimension(fixed["height"])
    }
  end

  defp parse_dimension(nil), do: 0

  defp parse_dimension(val) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp parse_dimension(val) when is_integer(val), do: val
  defp parse_dimension(_), do: 0
end
