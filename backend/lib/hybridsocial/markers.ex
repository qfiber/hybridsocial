defmodule Hybridsocial.Markers do
  @moduledoc """
  Context for timeline read markers (home, notifications).
  """

  import Ecto.Query
  alias Hybridsocial.Repo
  alias Hybridsocial.Markers.Marker

  @valid_timelines ["home", "notifications"]

  @doc "Get markers for the given identity and timeline names."
  def get_markers(identity_id, timelines \\ @valid_timelines) do
    timelines = Enum.filter(timelines, &(&1 in @valid_timelines))

    Marker
    |> where([m], m.identity_id == ^identity_id and m.timeline in ^timelines)
    |> Repo.all()
    |> Map.new(fn m -> {m.timeline, m} end)
  end

  @doc "Update (upsert) a marker for the given identity and timeline."
  def upsert_marker(identity_id, timeline, last_read_id)
      when timeline in @valid_timelines and is_binary(last_read_id) do
    attrs = %{
      identity_id: identity_id,
      timeline: timeline,
      last_read_id: last_read_id
    }

    %Marker{}
    |> Marker.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:last_read_id, :updated_at]},
      conflict_target: [:identity_id, :timeline],
      returning: true
    )
  end

  def upsert_marker(_, _, _), do: {:error, :invalid_timeline}

  @doc "Update multiple markers at once."
  def upsert_markers(identity_id, markers_params) when is_map(markers_params) do
    results =
      Enum.map(markers_params, fn {timeline, %{"last_read_id" => last_read_id}} ->
        {timeline, upsert_marker(identity_id, timeline, last_read_id)}
      end)

    errors = Enum.filter(results, fn {_, result} -> match?({:error, _}, result) end)

    if Enum.empty?(errors) do
      {:ok, get_markers(identity_id)}
    else
      {:error, :partial_failure}
    end
  end
end
