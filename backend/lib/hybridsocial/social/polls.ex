defmodule Hybridsocial.Social.Polls do
  @moduledoc """
  Context module for managing polls, poll options, and poll votes.
  """
  import Ecto.Query
  alias Hybridsocial.Repo
  alias Hybridsocial.Social.{Poll, PollOption, PollVote}

  def create_poll(post_id, attrs) do
    options = Map.get(attrs, "options", [])
    multiple_choice = Map.get(attrs, "multiple_choice", false)
    expires_at = Map.get(attrs, "expires_at")

    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.insert(:poll, fn _ ->
        %Poll{}
        |> Poll.changeset(%{
          post_id: post_id,
          multiple_choice: multiple_choice,
          expires_at: parse_expires_at(expires_at)
        })
      end)
      |> Ecto.Multi.run(:options, fn _repo, %{poll: poll} ->
        insert_options(poll.id, options)
      end)

    case Repo.transaction(multi) do
      {:ok, %{poll: poll, options: options}} ->
        {:ok, %{poll | options: options}}

      {:error, :poll, changeset, _} ->
        {:error, changeset}

      {:error, :options, reason, _} ->
        {:error, reason}
    end
  end

  def get_poll(post_id) do
    Poll
    |> where([p], p.post_id == ^post_id)
    |> Repo.one()
    |> case do
      nil -> nil
      poll -> Repo.preload(poll, [:options, :votes])
    end
  end

  def get_poll_by_id(poll_id) do
    Poll
    |> Repo.get(poll_id)
    |> case do
      nil -> nil
      poll -> Repo.preload(poll, [:options, :votes])
    end
  end

  def vote(poll_id, identity_id, option_ids) when is_list(option_ids) do
    with {:ok, poll} <- get_existing_poll(poll_id),
         :ok <- check_not_expired(poll),
         :ok <- check_options_valid(poll_id, option_ids),
         :ok <- check_vote_eligibility(poll, identity_id) do
      multi =
        option_ids
        |> Enum.with_index()
        |> Enum.reduce(Ecto.Multi.new(), fn {option_id, idx}, multi ->
          Ecto.Multi.insert(multi, {:vote, idx}, fn _ ->
            %PollVote{}
            |> PollVote.changeset(%{
              poll_id: poll_id,
              option_id: option_id,
              identity_id: identity_id
            })
          end)
        end)

      case Repo.transaction(multi) do
        {:ok, results} ->
          # Update votes_count for each option
          Enum.each(option_ids, fn option_id ->
            update_option_votes_count(option_id)
          end)

          # Update voters_count on poll
          update_voters_count(poll_id)

          votes = results |> Map.values()
          {:ok, votes}

        {:error, _, changeset, _} ->
          {:error, changeset}
      end
    end
  end

  def has_voted?(poll_id, identity_id) do
    PollVote
    |> where([v], v.poll_id == ^poll_id and v.identity_id == ^identity_id)
    |> Repo.exists?()
  end

  def get_votes(poll_id, identity_id) do
    PollVote
    |> where([v], v.poll_id == ^poll_id and v.identity_id == ^identity_id)
    |> Repo.all()
  end

  def poll_expired?(poll) do
    case poll.expires_at do
      nil -> false
      expires_at -> DateTime.compare(DateTime.utc_now(), expires_at) == :gt
    end
  end

  # --- Private helpers ---

  defp get_existing_poll(poll_id) do
    case Repo.get(Poll, poll_id) do
      nil -> {:error, :not_found}
      poll -> {:ok, Repo.preload(poll, :options)}
    end
  end

  defp check_not_expired(poll) do
    if poll_expired?(poll) do
      {:error, :poll_expired}
    else
      :ok
    end
  end

  defp check_options_valid(poll_id, option_ids) do
    valid_count =
      PollOption
      |> where([o], o.poll_id == ^poll_id and o.id in ^option_ids)
      |> Repo.aggregate(:count)

    if valid_count == length(option_ids) do
      :ok
    else
      {:error, :invalid_options}
    end
  end

  defp check_vote_eligibility(poll, identity_id) do
    if has_voted?(poll.id, identity_id) and not poll.multiple_choice do
      {:error, :already_voted}
    else
      :ok
    end
  end

  defp insert_options(poll_id, options) do
    results =
      options
      |> Enum.with_index()
      |> Enum.map(fn {text, index} ->
        %PollOption{}
        |> PollOption.changeset(%{poll_id: poll_id, text: text, position: index})
        |> Repo.insert()
      end)

    case Enum.find(results, fn {status, _} -> status == :error end) do
      nil -> {:ok, Enum.map(results, fn {:ok, option} -> option end)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_expires_at(nil), do: nil

  defp parse_expires_at(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> DateTime.truncate(dt, :microsecond)
      _ -> nil
    end
  end

  defp parse_expires_at(%DateTime{} = dt), do: DateTime.truncate(dt, :microsecond)

  defp update_option_votes_count(option_id) do
    count =
      PollVote
      |> where([v], v.option_id == ^option_id)
      |> Repo.aggregate(:count)

    PollOption
    |> where([o], o.id == ^option_id)
    |> Repo.update_all(set: [votes_count: count])
  end

  defp update_voters_count(poll_id) do
    count =
      PollVote
      |> where([v], v.poll_id == ^poll_id)
      |> select([v], count(v.identity_id, :distinct))
      |> Repo.one()

    Poll
    |> where([p], p.id == ^poll_id)
    |> Repo.update_all(set: [voters_count: count])
  end
end
