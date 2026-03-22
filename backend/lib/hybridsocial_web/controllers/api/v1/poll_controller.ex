defmodule HybridsocialWeb.Api.V1.PollController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Social.Polls

  # GET /api/v1/polls/:id
  def show(conn, %{"id" => poll_id}) do
    case Polls.get_poll_by_id(poll_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "poll.not_found"})

      poll ->
        conn
        |> put_status(:ok)
        |> json(serialize_poll(poll))
    end
  end

  # POST /api/v1/polls/:id/votes
  def vote(conn, %{"id" => poll_id} = params) do
    identity = conn.assigns.current_identity
    option_ids = Map.get(params, "choices", [])

    case Polls.vote(poll_id, identity.id, option_ids) do
      {:ok, _votes} ->
        poll = Polls.get_poll_by_id(poll_id)

        conn
        |> put_status(:ok)
        |> json(serialize_poll(poll))

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "poll.not_found"})

      {:error, :poll_expired} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "poll.expired"})

      {:error, :invalid_options} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "poll.invalid_options"})

      {:error, :already_voted} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "poll.already_voted"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  defp serialize_poll(poll) do
    %{
      id: poll.id,
      post_id: poll.post_id,
      multiple_choice: poll.multiple_choice,
      expires_at: poll.expires_at,
      voters_count: poll.voters_count,
      options:
        Enum.map(poll.options, fn opt ->
          %{
            id: opt.id,
            text: opt.text,
            position: opt.position,
            votes_count: opt.votes_count
          }
        end)
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
