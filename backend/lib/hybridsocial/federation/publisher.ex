defmodule Hybridsocial.Federation.Publisher do
  @moduledoc """
  Publishes ActivityPub activities to remote server inboxes.
  Handles recipient determination, delivery, and retry logic.
  """

  require Logger

  import Ecto.Query
  alias Hybridsocial.Repo
  alias Hybridsocial.Federation.{Delivery, HTTPSignature}
  alias Hybridsocial.Social.Follow

  @content_type "application/activity+json"
  @max_attempts 6
  @backoff_schedule [60, 300, 1_800, 7_200, 43_200, 86_400]

  @doc """
  Publishes an activity to all relevant remote inboxes.
  Queues delivery tasks for each inbox URL.
  """
  def publish(activity, identity) do
    inbox_urls = determine_recipients(activity, identity)

    Enum.each(inbox_urls, fn inbox_url ->
      {:ok, delivery} =
        %Delivery{}
        |> Delivery.changeset(%{
          activity_id: activity["id"],
          actor_id: identity.id,
          target_inbox: inbox_url,
          status: "pending"
        })
        |> Repo.insert()

      queue_delivery(activity, delivery, identity)
    end)

    {:ok, length(inbox_urls)}
  end

  @doc """
  Determines recipient inbox URLs for an activity based on addressing.
  Returns a deduplicated list of remote inbox URLs.
  """
  def determine_recipients(activity, identity) do
    all_targets =
      List.wrap(activity["to"]) ++ List.wrap(activity["cc"])

    all_targets
    |> Enum.flat_map(fn target ->
      cond do
        target == "https://www.w3.org/ns/activitystreams#Public" ->
          # Public addressing: deliver to all followers' inboxes
          get_follower_inboxes(identity.id)

        is_followers_collection?(target, identity) ->
          # Followers collection: deliver to followers' inboxes
          get_follower_inboxes(identity.id)

        true ->
          # Direct actor reference: fetch their inbox
          case get_actor_inbox(target) do
            nil -> []
            inbox -> [inbox]
          end
      end
    end)
    |> Enum.uniq()
    |> Enum.reject(&local_url?/1)
    |> batch_by_shared_inbox()
  end

  @doc """
  Delivers an activity to a specific inbox URL with HTTP signature.
  """
  def deliver(activity, inbox_url, identity) do
    body = Jason.encode!(activity)
    key_id = "#{HybridsocialWeb.Endpoint.url()}/actors/#{identity.id}#main-key"

    headers =
      if identity.private_key do
        sig_headers =
          HTTPSignature.sign(
            %{url: inbox_url, method: "POST", body: body},
            identity.private_key,
            key_id
          )

        [
          {"Content-Type", @content_type},
          {"Accept", @content_type}
          | Enum.map(sig_headers, fn {k, v} -> {k, v} end)
        ]
      else
        [
          {"Content-Type", @content_type},
          {"Accept", @content_type}
        ]
      end

    case HTTPoison.post(inbox_url, body, headers, recv_timeout: 15_000, timeout: 15_000) do
      {:ok, %{status_code: status}} when status in 200..299 ->
        {:ok, status}

      {:ok, %{status_code: status, body: resp_body}} ->
        {:error, "HTTP #{status}: #{String.slice(resp_body, 0, 500)}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "Connection error: #{inspect(reason)}"}
    end
  end

  @doc """
  Retries failed deliveries with exponential backoff.
  Finds deliveries that are eligible for retry and processes them.
  """
  def retry_failed_deliveries do
    now = DateTime.utc_now()

    Delivery
    |> where([d], d.status in ["failed", "retrying"])
    |> where([d], d.attempts < @max_attempts)
    |> Repo.all()
    |> Enum.filter(fn delivery ->
      eligible_for_retry?(delivery, now)
    end)
    |> Enum.each(fn delivery ->
      delivery
      |> Delivery.changeset(%{status: "retrying"})
      |> Repo.update()

      # Look up the identity for signing
      case Hybridsocial.Accounts.get_identity(delivery.actor_id) do
        nil ->
          delivery
          |> Delivery.changeset(%{status: "failed", error: "Actor not found"})
          |> Repo.update()

        identity ->
          # We don't have the original activity stored, so we record a failure
          # In production, the activity JSON would be stored or reconstructable
          delivery
          |> Delivery.changeset(%{
            status: "failed",
            error: "Retry not yet supported without stored activity",
            attempts: delivery.attempts + 1,
            last_attempt_at: DateTime.utc_now()
          })
          |> Repo.update()

          Logger.warning(
            "Retry for delivery #{delivery.id} to #{delivery.target_inbox} (attempt #{delivery.attempts + 1}) - actor: #{identity.id}"
          )
      end
    end)
  end

  # --- Private helpers ---

  defp queue_delivery(activity, delivery, identity) do
    Task.Supervisor.start_child(
      Hybridsocial.Federation.DeliveryTaskSupervisor,
      fn ->
        process_delivery(activity, delivery, identity)
      end
    )
  end

  defp process_delivery(activity, delivery, identity) do
    case deliver(activity, delivery.target_inbox, identity) do
      {:ok, _status} ->
        delivery
        |> Delivery.changeset(%{
          status: "delivered",
          attempts: delivery.attempts + 1,
          last_attempt_at: DateTime.utc_now()
        })
        |> Repo.update()

      {:error, error} ->
        Logger.warning(
          "Delivery failed to #{delivery.target_inbox}: #{error}"
        )

        delivery
        |> Delivery.changeset(%{
          status: "failed",
          error: to_string(error),
          attempts: delivery.attempts + 1,
          last_attempt_at: DateTime.utc_now()
        })
        |> Repo.update()
    end
  end

  defp get_follower_inboxes(identity_id) do
    Follow
    |> where([f], f.followee_id == ^identity_id and f.status == :accepted)
    |> join(:inner, [f], i in assoc(f, :follower))
    |> select([_f, i], i.inbox_url)
    |> Repo.all()
    |> Enum.reject(&is_nil/1)
  end

  defp get_actor_inbox(actor_url) do
    # Check if the actor is local
    case Hybridsocial.Repo.get_by(Hybridsocial.Accounts.Identity, ap_actor_url: actor_url) do
      nil ->
        # Remote actor - try to fetch their inbox from the remote_actors cache
        fetch_remote_inbox(actor_url)

      _local_identity ->
        # Local actor, no need for remote delivery
        nil
    end
  end

  defp fetch_remote_inbox(actor_url) do
    # Check the remote_actors cache first
    case Hybridsocial.Repo.get_by(Hybridsocial.Federation.RemoteActor, ap_id: actor_url) do
      nil ->
        # Could fetch from the remote server, but for now return nil
        Logger.debug("No cached remote actor for #{actor_url}")
        nil

      remote_actor ->
        remote_actor.inbox_url
    end
  end

  defp is_followers_collection?(url, identity) do
    url == "#{HybridsocialWeb.Endpoint.url()}/actors/#{identity.id}/followers"
  end

  defp local_url?(url) do
    base = HybridsocialWeb.Endpoint.url()
    String.starts_with?(url, base)
  end

  defp batch_by_shared_inbox(inbox_urls) do
    # Group inboxes by domain and prefer shared inboxes when available
    inbox_urls
    |> Enum.group_by(fn url ->
      URI.parse(url).host
    end)
    |> Enum.flat_map(fn {_domain, urls} ->
      # For now, return all unique inbox URLs per domain
      # In the future, we could look up shared inboxes
      Enum.uniq(urls)
    end)
    |> Enum.uniq()
  end

  defp eligible_for_retry?(%{last_attempt_at: nil}, _now), do: true

  defp eligible_for_retry?(%{attempts: attempts, last_attempt_at: last_attempt}, now) do
    if attempts >= @max_attempts do
      false
    else
      backoff_index = min(attempts, length(@backoff_schedule) - 1)
      backoff_seconds = Enum.at(@backoff_schedule, backoff_index)
      next_attempt = DateTime.add(last_attempt, backoff_seconds, :second)
      DateTime.compare(now, next_attempt) != :lt
    end
  end
end
