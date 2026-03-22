defmodule Hybridsocial.Content.ScheduledPosts do
  @moduledoc """
  Context module for managing scheduled posts.
  """
  import Ecto.Query
  alias Hybridsocial.Repo
  alias Hybridsocial.Social.Post

  @doc """
  Schedules a post for future publishing.
  Creates a post with scheduled_at in the future and published_at = nil.
  """
  def schedule_post(identity_id, attrs) do
    scheduled_at = Map.get(attrs, "scheduled_at")

    with {:ok, parsed_time} <- parse_scheduled_at(scheduled_at),
         :ok <- validate_future(parsed_time) do
      post_attrs =
        attrs
        |> Map.put("identity_id", identity_id)
        |> Map.put("scheduled_at", parsed_time)

      %Post{}
      |> Post.create_changeset(post_attrs)
      |> Ecto.Changeset.put_change(:scheduled_at, parsed_time)
      |> Repo.insert()
    end
  end

  @doc """
  Lists a user's scheduled (unpublished) posts.
  """
  def get_scheduled_posts(identity_id) do
    Post
    |> where([p], p.identity_id == ^identity_id)
    |> where([p], not is_nil(p.scheduled_at))
    |> where([p], is_nil(p.published_at))
    |> where([p], is_nil(p.deleted_at))
    |> order_by([p], asc: p.scheduled_at)
    |> Repo.all()
  end

  @doc """
  Cancels (deletes) a scheduled post.
  """
  def cancel_scheduled_post(post_id, identity_id) do
    with {:ok, post} <- get_owned_scheduled_post(post_id, identity_id) do
      Repo.delete(post)
    end
  end

  @doc """
  Updates a scheduled post before it's published.
  """
  def update_scheduled_post(post_id, identity_id, attrs) do
    with {:ok, post} <- get_owned_scheduled_post(post_id, identity_id) do
      scheduled_at = Map.get(attrs, "scheduled_at")

      changeset =
        post
        |> Ecto.Changeset.cast(attrs, [:content, :visibility, :sensitive, :spoiler_text])
        |> Ecto.Changeset.validate_required([:content])
        |> Ecto.Changeset.validate_length(:content, max: 10_000)

      changeset =
        if scheduled_at do
          case parse_scheduled_at(scheduled_at) do
            {:ok, parsed_time} ->
              case validate_future(parsed_time) do
                :ok -> Ecto.Changeset.put_change(changeset, :scheduled_at, parsed_time)
                {:error, reason} -> Ecto.Changeset.add_error(changeset, :scheduled_at, reason)
              end

            {:error, _} ->
              Ecto.Changeset.add_error(changeset, :scheduled_at, "invalid format")
          end
        else
          changeset
        end

      Repo.update(changeset)
    end
  end

  @doc """
  Publishes all posts whose scheduled_at time has passed.
  Sets published_at to now for each due post.
  """
  def publish_due_posts do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Post
    |> where([p], not is_nil(p.scheduled_at))
    |> where([p], p.scheduled_at <= ^now)
    |> where([p], is_nil(p.published_at))
    |> where([p], is_nil(p.deleted_at))
    |> Repo.update_all(set: [published_at: now])
  end

  # --- Private helpers ---

  defp get_owned_scheduled_post(post_id, identity_id) do
    Post
    |> where([p], not is_nil(p.scheduled_at))
    |> where([p], is_nil(p.published_at))
    |> where([p], is_nil(p.deleted_at))
    |> Repo.get(post_id)
    |> case do
      nil -> {:error, :not_found}
      %Post{identity_id: ^identity_id} = post -> {:ok, post}
      _post -> {:error, :forbidden}
    end
  end

  defp parse_scheduled_at(nil), do: {:error, "scheduled_at is required"}

  defp parse_scheduled_at(%DateTime{} = dt), do: {:ok, DateTime.truncate(dt, :microsecond)}

  defp parse_scheduled_at(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> {:ok, DateTime.truncate(dt, :microsecond)}
      {:error, _} -> {:error, "invalid format"}
    end
  end

  defp parse_scheduled_at(_), do: {:error, "invalid format"}

  defp validate_future(dt) do
    if DateTime.compare(dt, DateTime.utc_now()) == :gt do
      :ok
    else
      {:error, "must be in the future"}
    end
  end
end
