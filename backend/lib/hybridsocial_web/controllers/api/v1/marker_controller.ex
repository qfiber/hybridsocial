defmodule HybridsocialWeb.Api.V1.MarkerController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Markers

  @doc "GET /api/v1/markers — get markers for home and notifications."
  def index(conn, params) do
    identity = conn.assigns.current_identity

    timelines =
      case params["timeline"] do
        timelines when is_list(timelines) -> timelines
        timeline when is_binary(timeline) -> [timeline]
        _ -> ["home", "notifications"]
      end

    markers = Markers.get_markers(identity.id, timelines)

    conn
    |> json(render_markers(markers))
  end

  @doc "POST /api/v1/markers — update markers."
  def create(conn, params) do
    identity = conn.assigns.current_identity

    marker_params =
      params
      |> Map.take(["home", "notifications"])

    case Markers.upsert_markers(identity.id, marker_params) do
      {:ok, markers} ->
        conn |> json(render_markers(markers))

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: inspect(reason)})
    end
  end

  defp render_markers(markers) do
    Map.new(markers, fn {timeline, marker} ->
      {timeline, %{
        last_read_id: marker.last_read_id,
        version: 0,
        updated_at: marker.updated_at
      }}
    end)
  end
end
