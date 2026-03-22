defmodule Hybridsocial.Social.Streams do
  @moduledoc """
  Context for video stream (reels) view tracking and streams feed.
  """
  import Ecto.Query

  alias Hybridsocial.Repo
  alias Hybridsocial.Social.{StreamView, Post}

  @default_limit 20
  @max_limit 40

  @doc """
  Records a view event for a video stream post.
  """
  def record_view(post_id, identity_id, attrs) do
    %StreamView{}
    |> StreamView.changeset(
      Map.merge(attrs, %{
        "post_id" => post_id,
        "identity_id" => identity_id
      })
    )
    |> Repo.insert()
  end

  @doc """
  Returns view statistics for a given post.

  Returns a map with:
    - total_views
    - unique_viewers
    - avg_watch_duration
    - completion_rate
    - replay_rate
  """
  def get_view_stats(post_id) do
    query =
      StreamView
      |> where([sv], sv.post_id == ^post_id)

    total_views = Repo.aggregate(query, :count)

    if total_views == 0 do
      %{
        total_views: 0,
        unique_viewers: 0,
        avg_watch_duration: 0.0,
        completion_rate: 0.0,
        replay_rate: 0.0
      }
    else
      unique_viewers =
        query
        |> where([sv], not is_nil(sv.identity_id))
        |> select([sv], count(sv.identity_id, :distinct))
        |> Repo.one()

      avg_watch_duration =
        query
        |> select([sv], avg(sv.watch_duration))
        |> Repo.one() || 0.0

      completed_count =
        query
        |> where([sv], sv.completed == true)
        |> Repo.aggregate(:count)

      replayed_count =
        query
        |> where([sv], sv.replayed == true)
        |> Repo.aggregate(:count)

      %{
        total_views: total_views,
        unique_viewers: unique_viewers,
        avg_watch_duration: avg_watch_duration |> to_float(),
        completion_rate: to_float(completed_count / total_views * 100),
        replay_rate: to_float(replayed_count / total_views * 100)
      }
    end
  end

  @doc """
  Returns the video streams feed: public video_stream posts ordered by
  engagement (reaction_count) with time decay, cursor paginated.
  """
  def streams_feed(_viewer_id, opts \\ []) do
    limit = parse_limit(opts)

    query =
      Post
      |> where([p], p.post_type == "video_stream")
      |> where([p], p.visibility == "public")
      |> where([p], is_nil(p.deleted_at))
      |> apply_cursor_filters(opts)
      |> order_by([p], [desc: p.reaction_count, desc: p.inserted_at])
      |> limit(^limit)
      |> preload(:identity)

    Repo.all(query)
  end

  # --- Private helpers ---

  defp parse_limit(opts) do
    opts
    |> Keyword.get(:limit, @default_limit)
    |> min(@max_limit)
    |> max(1)
  end

  defp apply_cursor_filters(query, opts) do
    query
    |> maybe_max_id(Keyword.get(opts, :max_id))
    |> maybe_min_id(Keyword.get(opts, :min_id))
  end

  defp maybe_max_id(query, nil), do: query
  defp maybe_max_id(query, max_id), do: where(query, [p], p.id < ^max_id)

  defp maybe_min_id(query, nil), do: query
  defp maybe_min_id(query, min_id), do: where(query, [p], p.id > ^min_id)

  defp to_float(value) when is_float(value), do: value
  defp to_float(value) when is_integer(value), do: value / 1
  defp to_float(%Decimal{} = value), do: Decimal.to_float(value)
  defp to_float(_), do: 0.0
end
