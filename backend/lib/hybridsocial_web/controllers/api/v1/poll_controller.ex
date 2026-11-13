defmodule HybridsocialWeb.Api.V1.PollController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Social.Polls
  alias Hybridsocial.Social.{Poll, PollOption, Post}
  alias Hybridsocial.Repo
  import Ecto.Query, only: [from: 2]

  # GET /api/v1/polls/:id
  def show(conn, %{"id" => poll_id}) do
    viewer_id =
      case conn.assigns[:current_identity] do
        %{id: id} -> id
        _ -> nil
      end

    case Polls.get_poll_by_id(poll_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "poll.not_found"})

      poll ->
        conn
        |> put_status(:ok)
        |> json(serialize_poll(poll, viewer_id))
    end
  end

  # GET /api/v1/polls/:id/voters
  #
  # Returns the distinct identities who have cast at least one vote on
  # this poll. Per the user-facing requirement, this exposes *who*
  # voted but not *what* they voted — the option_id is intentionally
  # not selected. Multi-choice polls collapse multiple PollVote rows
  # for the same identity to a single voter entry.
  def voters(conn, %{"id" => poll_id}) do
    case Polls.get_poll_by_id(poll_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "poll.not_found"})

      _poll ->
        voters =
          from(v in Hybridsocial.Social.PollVote,
            where: v.poll_id == ^poll_id,
            join: i in Hybridsocial.Accounts.Identity,
            on: i.id == v.identity_id,
            distinct: i.id,
            order_by: [asc: v.inserted_at],
            select: i
          )
          |> Repo.all()

        conn
        |> put_status(:ok)
        |> json(%{
          voters:
            Enum.map(voters, fn i ->
              %{
                id: i.id,
                handle: i.handle,
                acct: HybridsocialWeb.Helpers.Account.build_acct(i),
                display_name: i.display_name,
                avatar_url: HybridsocialWeb.Helpers.Account.remote_image(i.avatar_url),
                url: Map.get(i, :url)
              }
            end),
          total: length(voters)
        })
    end
  end

  # POST /api/v1/polls/:id/votes
  def vote(conn, %{"id" => poll_id} = params) do
    identity = conn.assigns.current_identity
    raw_choices = Map.get(params, "choices", [])

    # Frontend (Mastodon convention) sends 0-based option indices.
    # Resolve them to PollOption ids by looking up the poll's
    # options in `position` order. Anything that's already a uuid
    # passes through unchanged so other clients calling with ids
    # still work.
    option_ids = resolve_choice_ids(poll_id, raw_choices)

    case Polls.vote(poll_id, identity.id, option_ids) do
      {:ok, _votes} ->
        # Fan the vote out to the origin instance when the poll lives
        # remote. Mastodon-style: one Create-Note activity per chosen
        # option, with `inReplyTo: question.ap_id` and `name: option.text`.
        # Best-effort — local state is already correct for the voter.
        federate_vote_if_remote(identity, poll_id, option_ids)

        poll = Polls.get_poll_by_id(poll_id)

        conn
        |> put_status(:ok)
        |> json(serialize_poll(poll, identity.id))

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

  # Mastodon-shaped poll object — same fields the post serializer
  # emits inside `post.poll`, so the client's vote-completion path can
  # swap the new poll into `post.poll` without remapping shapes.
  defp serialize_poll(poll, viewer_id) do
    options = Enum.sort_by(poll.options, & &1.position)

    own_votes_set =
      if viewer_id do
        from(v in Hybridsocial.Social.PollVote,
          where: v.poll_id == ^poll.id and v.identity_id == ^viewer_id,
          select: v.option_id
        )
        |> Repo.all()
        |> MapSet.new()
      else
        MapSet.new()
      end

    own_indices =
      options
      |> Enum.with_index()
      |> Enum.flat_map(fn {opt, idx} ->
        if MapSet.member?(own_votes_set, opt.id), do: [idx], else: []
      end)

    votes_count = Enum.reduce(options, 0, fn o, acc -> acc + (o.votes_count || 0) end)

    %{
      id: poll.id,
      expires_at: poll.expires_at,
      expired: poll_expired?(poll.expires_at),
      multiple: poll.multiple_choice,
      votes_count: votes_count,
      voters_count: poll.voters_count,
      voted: own_indices != [],
      own_votes: own_indices,
      options:
        Enum.map(options, fn opt ->
          %{title: opt.text, votes_count: opt.votes_count}
        end)
    }
  end

  defp poll_expired?(nil), do: false

  defp poll_expired?(%DateTime{} = expires_at),
    do: DateTime.compare(DateTime.utc_now(), expires_at) == :gt

  defp poll_expired?(%NaiveDateTime{} = expires_at) do
    case DateTime.from_naive(expires_at, "Etc/UTC") do
      {:ok, dt} -> DateTime.compare(DateTime.utc_now(), dt) == :gt
      _ -> false
    end
  end

  defp poll_expired?(_), do: false

  defp resolve_choice_ids(poll_id, raw_choices) do
    options =
      from(o in PollOption, where: o.poll_id == ^poll_id, order_by: [asc: o.position])
      |> Repo.all()

    Enum.flat_map(raw_choices, fn choice ->
      cond do
        is_integer(choice) ->
          case Enum.at(options, choice) do
            nil -> []
            opt -> [opt.id]
          end

        is_binary(choice) and byte_size(choice) == 36 ->
          # Looks like a UUID — pass through.
          [choice]

        is_binary(choice) ->
          # String form of an integer index ("0", "1"). Same as
          # the integer branch above.
          case Integer.parse(choice) do
            {n, ""} ->
              case Enum.at(options, n) do
                nil -> []
                opt -> [opt.id]
              end

            _ ->
              []
          end

        true ->
          []
      end
    end)
  end

  defp federate_vote_if_remote(identity, poll_id, option_ids) do
    # Pull poll → post → check ap_id. Only remote posts have an ap_id
    # outside our base url; everything local handles voting on its own.
    case Repo.one(
           from p in Poll,
             where: p.id == ^poll_id,
             join: post in Post,
             on: post.id == p.post_id,
             preload: [post: :identity]
         ) do
      nil ->
        :ok

      poll ->
        post = poll.post

        if remote_post?(post) and is_binary(post.ap_id) do
          options =
            from(o in PollOption,
              where: o.poll_id == ^poll_id and o.id in ^option_ids
            )
            |> Repo.all()

          identity = Repo.preload(identity, [])
          deliver_poll_votes(identity, post, options)
        end

        :ok
    end
  end

  # Fan a remote poll vote out to the author's inbox as individual
  # Create activities. No-op unless we hold the voter's signing key.
  defp deliver_poll_votes(%{private_key: nil}, _post, _options), do: :ok

  defp deliver_poll_votes(identity, post, options) do
    Hybridsocial.Federation.deliver_async(fn ->
      for option <- options do
        activity =
          Hybridsocial.Federation.ActivityBuilder.build_poll_vote(identity, post, option)

        Hybridsocial.Federation.Publisher.publish(activity, identity)
      end
    end)

    :ok
  end

  defp remote_post?(%Post{identity: %{ap_actor_url: ap}}) when is_binary(ap) do
    base = HybridsocialWeb.Endpoint.url()
    not String.starts_with?(ap, base)
  end

  defp remote_post?(_), do: false

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
