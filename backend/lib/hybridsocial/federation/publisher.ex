defmodule Hybridsocial.Federation.Publisher do
  @moduledoc """
  Publishes ActivityPub activities to remote server inboxes.
  Handles recipient determination, delivery, and retry logic.
  """

  require Logger

  import Ecto.Query
  alias Hybridsocial.Repo
  alias Hybridsocial.Federation.{CircuitBreaker, Delivery, HTTPSignature}
  alias Hybridsocial.Social.Follow

  @content_type "application/activity+json"
  @max_attempts 6
  @backoff_schedule [60, 300, 1_800, 7_200, 43_200, 86_400]
  # A "retrying" row older than this is assumed stuck (node restarted).
  @stuck_retrying_seconds 600

  @doc """
  Publishes an activity to all relevant remote inboxes.
  Queues delivery tasks for each inbox URL.
  """
  def publish(activity, identity) do
    # Drop peers we won't attempt *before* we write queue rows: switched off
    # by an admin, or with an open circuit not yet due for a probe. Either
    # way the row could only end "Skipped" (failed rows aren't replayed),
    # one dead letter per activity per follower on a dead peer. Once a
    # circuit is due, its next activity goes out as the half-open probe.
    inbox_urls =
      activity
      |> determine_recipients(identity)
      |> reject_blocked_inboxes()

    Enum.each(inbox_urls, fn inbox_url ->
      {:ok, delivery} =
        %Delivery{}
        |> Delivery.changeset(%{
          activity_id: activity["id"],
          activity_type: activity["type"],
          activity_body: activity,
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

    is_public = Enum.any?(all_targets, &(&1 == "https://www.w3.org/ns/activitystreams#Public"))

    base =
      all_targets
      |> Enum.flat_map(fn target ->
        cond do
          target == "https://www.w3.org/ns/activitystreams#Public" ->
            # Public addressing: deliver to all followers' inboxes
            get_follower_inboxes(identity.id)

          followers_collection?(target, identity) ->
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

    # Fan out every public activity (Create, Announce, etc.) to every
    # accepted relay too. Relays re-broadcast public posts to other
    # subscribing instances, which is the whole point of relays for
    # small/new servers that have no direct followers yet.
    with_relays = if is_public, do: base ++ accepted_relay_inboxes(), else: base

    with_relays
    |> Enum.uniq()
    |> Enum.reject(&local_url?/1)
    |> batch_by_shared_inbox()
  end

  defp accepted_relay_inboxes do
    import Ecto.Query
    alias Hybridsocial.Federation.Relay

    Repo.all(from r in Relay, where: r.status == "accepted", select: r.inbox_url)
  end

  @doc """
  Delivers an activity to a specific inbox URL with HTTP signature.

  Refuses to deliver if `identity.private_key` is nil — every modern
  fediverse server rejects unsigned activity POSTs, so silently sending
  an unsigned request would produce confusing "Invalid HTTP Signature"
  failures from the remote and waste retry budget. The caller surfaces
  this as a delivery failure into the dead-letter queue, where the
  missing key shows up as a real signal.
  """
  def deliver(activity, inbox_url, identity) do
    if is_nil(identity.private_key) do
      Logger.error(
        "Federation delivery refused: identity #{identity.id} has no private_key " <>
          "(would have sent unsigned POST to #{inbox_url}). " <>
          "Re-run key generation for this identity."
      )

      {:error, "missing_private_key"}
    else
      body = Jason.encode!(activity)
      # Use the identity's stored ActivityPub URL so imported actors sign
      # with the keyId remote servers already have cached. Native
      # identities store the `/actors/<uuid>` form, so this is unchanged
      # for them.
      actor_url =
        identity.ap_actor_url || "#{HybridsocialWeb.Endpoint.url()}/actors/#{identity.id}"

      key_id = "#{actor_url}#main-key"

      sig_headers =
        HTTPSignature.sign(
          %{url: inbox_url, method: "POST", body: body},
          identity.private_key,
          key_id
        )

      headers = [
        {"Content-Type", @content_type},
        {"Accept", @content_type}
        | Enum.map(sig_headers, fn {k, v} -> {k, v} end)
      ]

      # Time the network call so the admin Delivery Queue tab can chart
      # p50/p95 latency per destination. Wall-clock includes DNS,
      # connect, TLS handshake, request, and read — same thing a real
      # client would experience.
      if CircuitBreaker.allow?(inbox_url) do
        started_at_ns = System.monotonic_time(:nanosecond)

        {result, category} =
          case Hybridsocial.HTTP.post(inbox_url, body, headers,
                 recv_timeout: 15_000,
                 timeout: 15_000
               ) do
            {:ok, %{status_code: status}} when status in 200..299 ->
              {{:ok, status}, :ok}

            {:ok, %{status_code: status, body: resp_body}} ->
              # Server answered — up, just rejected this activity. Soft: does
              # not trip the breaker (e.g. a 500 on one Delete, 404 per-user).
              {{:error, "HTTP #{status}: #{String.slice(resp_body, 0, 500)}"}, :soft}

            {:error, %Hybridsocial.HTTP.Error{reason: reason}} ->
              # Connection-level failure — the instance itself is down. Hard.
              {{:error, "Connection error: #{inspect(reason)}"}, :hard}
          end

        CircuitBreaker.record_result(inbox_url, category)

        duration_ms = div(System.monotonic_time(:nanosecond) - started_at_ns, 1_000_000)
        Process.put(:hs_last_delivery_ms, duration_ms)
        result
      else
        # Instance is in the open (persistently-unreachable) state — skip the
        # network call entirely until its next probe window. Cheap, so the
        # retry loop can keep flowing without hammering a dead host.
        {:error, "Skipped: instance circuit open (persistently unreachable)"}
      end
    end
  end

  @doc """
  Returns the duration in milliseconds of the most recent
  `deliver/3` or `deliver_as_instance/2` call on this process. Lets
  callers stamp the timing on their delivery row without changing
  the existing return contract (which the NATS consumer also
  depends on).
  """
  def last_delivery_duration_ms do
    Process.get(:hs_last_delivery_ms)
  end

  @doc """
  Delivers an activity signed with the instance actor's key (rather
  than a user identity's). Used for relay Follow/Undo activities,
  where the "actor" in the activity is the instance itself, not an
  individual user.
  """
  def deliver_as_instance(activity, inbox_url) do
    alias Hybridsocial.Federation.InstanceActor

    if InstanceActor.keys_configured?() do
      body = Jason.encode!(activity)
      key_id = "#{InstanceActor.ap_id()}#main-key"

      sig_headers =
        HTTPSignature.sign(
          %{url: inbox_url, method: "POST", body: body},
          InstanceActor.private_key(),
          key_id
        )

      headers = [
        {"Content-Type", @content_type},
        {"Accept", @content_type}
        | Enum.map(sig_headers, fn {k, v} -> {k, v} end)
      ]

      if CircuitBreaker.allow?(inbox_url) do
        {result, category} =
          case Hybridsocial.HTTP.post(inbox_url, body, headers,
                 recv_timeout: 15_000,
                 timeout: 15_000
               ) do
            {:ok, %{status_code: status}} when status in 200..299 ->
              {{:ok, status}, :ok}

            {:ok, %{status_code: status, body: resp_body}} ->
              {{:error, "HTTP #{status}: #{String.slice(resp_body, 0, 500)}"}, :soft}

            {:error, %Hybridsocial.HTTP.Error{reason: reason}} ->
              {{:error, "Connection error: #{inspect(reason)}"}, :hard}
          end

        CircuitBreaker.record_result(inbox_url, category)
        result
      else
        {:error, "Skipped: instance circuit open (persistently unreachable)"}
      end
    else
      Logger.error(
        "Federation delivery refused: instance actor has no keys configured " <>
          "(would have sent unsigned POST to #{inbox_url}). " <>
          "Run mix hybridsocial.gen.instance_keys."
      )

      {:error, "instance_keys_unconfigured"}
    end
  end

  @doc """
  Re-sends failed deliveries that failed for a transient reason. Runs from
  `DeliveryWorker` every few minutes.

  Each row stores the signed-over activity (`activity_body`), so a retry
  re-sends exactly what was first sent, freshly signed. A row is retried
  when all of these hold:

    * it failed on something a retry can fix: a connection error or
      timeout, a skipped send behind an open circuit, or HTTP 5xx (not 501),
      408 or 429. A peer that answered 4xx refused the activity itself.
    * it's younger than `federation_retry_window_hours` (default 48), so a
      peer coming back after a long outage doesn't get a flood of stale
      activities.
    * its backoff has elapsed (`@backoff_schedule`), under `@max_attempts`.
    * its peer isn't admin-disabled or behind an open circuit not yet due
      for a probe (it stays parked until then).

  Before re-sending, an activity that history has overtaken is retired
  instead: a Create/Update/Announce of a post since deleted (re-sending
  would resurrect it on the peer), or anything a later Undo to the same
  inbox cancelled.
  """
  def retry_failed_deliveries(now \\ DateTime.utc_now()) do
    cutoff = DateTime.add(now, -retry_window_hours() * 3600, :second)
    stuck_before = DateTime.add(now, -@stuck_retrying_seconds, :second)
    blocked = CircuitBreaker.blocked_domains()

    Delivery
    |> where([d], d.attempts < @max_attempts and d.inserted_at >= ^cutoff)
    |> where([d], not is_nil(d.activity_body))
    # A row marked "retrying" is in flight; only pick it up again if it has
    # been stuck there (the node restarted mid-send).
    |> where(
      [d],
      d.status == "failed" or (d.status == "retrying" and d.updated_at < ^stuck_before)
    )
    |> Repo.all()
    |> Enum.reject(&blocked_inbox?(&1, blocked))
    |> Enum.filter(&(transient_error?(&1.error) and eligible_for_retry?(&1, now)))
    |> Enum.each(&retry_delivery/1)
  end

  defp retry_delivery(%Delivery{} = delivery) do
    case Hybridsocial.Accounts.get_identity(delivery.actor_id) do
      nil ->
        retire(delivery, "Actor not found")

      identity ->
        if obsolete?(delivery) do
          retire(delivery, "Obsolete: overtaken by a later delete or undo")
        else
          # force: bump updated_at even for a stuck row already "retrying",
          # so the next sweep sees it as in flight, not stuck again.
          {:ok, delivery} =
            delivery |> Delivery.changeset(%{status: "retrying"}) |> Repo.update(force: true)

          queue_delivery(delivery.activity_body, delivery, identity)
        end
    end
  end

  # Parked for good: attempts at the cap keeps the sweep from picking it up.
  defp retire(delivery, reason) do
    delivery
    |> Delivery.changeset(%{status: "failed", error: reason, attempts: @max_attempts})
    |> Repo.update()
  end

  defp blocked_inbox?(%Delivery{target_inbox: inbox}, blocked) do
    case Hybridsocial.Federation.ActivityMapper.extract_domain(inbox) do
      nil -> false
      domain -> MapSet.member?(blocked, domain)
    end
  end

  @doc false
  def transient_error?("Connection error:" <> _), do: true
  def transient_error?("Skipped:" <> _), do: true

  def transient_error?("HTTP " <> rest) do
    case Integer.parse(rest) do
      {501, _} -> false
      {status, _} -> status >= 500 or status in [408, 429]
      :error -> false
    end
  end

  def transient_error?(_), do: false

  defp obsolete?(%Delivery{activity_body: body} = delivery) do
    activity_id = body["id"]

    object_deleted?(body) or
      (is_binary(activity_id) and undone_later?(delivery, activity_id))
  end

  defp object_deleted?(%{"type" => type} = body) when type in ["Create", "Update", "Announce"] do
    case object_id(body["object"]) do
      nil ->
        false

      id ->
        Hybridsocial.Social.Post
        |> where([p], p.ap_id == ^id and not is_nil(p.deleted_at))
        |> Repo.exists?()
    end
  end

  defp object_deleted?(_), do: false

  defp undone_later?(%Delivery{target_inbox: inbox, inserted_at: at}, activity_id) do
    Delivery
    |> where([d], d.target_inbox == ^inbox and d.activity_type == "Undo" and d.inserted_at > ^at)
    |> where(
      [d],
      fragment("?->'object'->>'id' = ?", d.activity_body, ^activity_id) or
        fragment("?->>'object' = ?", d.activity_body, ^activity_id)
    )
    |> Repo.exists?()
  end

  defp object_id(id) when is_binary(id), do: id
  defp object_id(%{"id" => id}) when is_binary(id), do: id
  defp object_id(_), do: nil

  defp retry_window_hours do
    case Hybridsocial.Config.get("federation_retry_window_hours", 48) do
      n when is_integer(n) and n > 0 -> n
      _ -> 48
    end
  end

  # --- Private helpers ---

  # Filters a list of inbox URLs down to peers we'll attempt right now.
  # One query per fan-out, and the blocked set is normally small.
  defp reject_blocked_inboxes([]), do: []

  defp reject_blocked_inboxes(inbox_urls) do
    blocked = CircuitBreaker.blocked_domains()

    if MapSet.size(blocked) == 0 do
      inbox_urls
    else
      Enum.reject(inbox_urls, fn url ->
        case Hybridsocial.Federation.ActivityMapper.extract_domain(url) do
          nil -> false
          domain -> MapSet.member?(blocked, domain)
        end
      end)
    end
  end

  defp queue_delivery(activity, delivery, identity) do
    # Deliver directly via Task.Supervisor for reliability
    Logger.info("Federation delivery queued for #{delivery.target_inbox}")

    Hybridsocial.Federation.deliver_async(fn ->
      process_delivery(activity, delivery, identity)
    end)
  end

  defp process_delivery(activity, delivery, identity) do
    case deliver(activity, delivery.target_inbox, identity) do
      {:ok, _status} ->
        delivery
        |> Delivery.changeset(%{
          status: "delivered",
          attempts: delivery.attempts + 1,
          last_attempt_at: DateTime.utc_now(),
          duration_ms: last_delivery_duration_ms()
        })
        |> Repo.update()

      {:error, error} ->
        Logger.warning("Delivery failed to #{delivery.target_inbox}: #{error}")

        delivery
        |> Delivery.changeset(%{
          status: "failed",
          error: to_string(error),
          attempts: delivery.attempts + 1,
          last_attempt_at: DateTime.utc_now(),
          duration_ms: last_delivery_duration_ms()
        })
        |> Repo.update()
    end
  end

  defp get_follower_inboxes(identity_id) do
    # Get individual inbox URLs from follower identities
    individual_inboxes =
      Follow
      |> where([f], f.followee_id == ^identity_id and f.status == :accepted)
      |> join(:inner, [f], i in assoc(f, :follower))
      |> select([_f, i], i.inbox_url)
      |> Repo.all()
      |> Enum.reject(&is_nil/1)

    # Also check remote_actors for shared inboxes matching follower ap_actor_urls
    follower_ap_ids =
      Follow
      |> where([f], f.followee_id == ^identity_id and f.status == :accepted)
      |> join(:inner, [f], i in assoc(f, :follower))
      |> where([_f, i], not is_nil(i.ap_actor_url))
      |> select([_f, i], i.ap_actor_url)
      |> Repo.all()

    shared_inboxes =
      if follower_ap_ids != [] do
        Hybridsocial.Federation.RemoteActor
        |> where([r], r.ap_id in ^follower_ap_ids and not is_nil(r.shared_inbox_url))
        |> select([r], r.shared_inbox_url)
        |> Repo.all()
      else
        []
      end

    (individual_inboxes ++ shared_inboxes)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp get_actor_inbox(actor_url) do
    base_url = HybridsocialWeb.Endpoint.url()

    if String.starts_with?(actor_url, base_url) do
      # Truly local actor — no remote delivery needed
      nil
    else
      # Remote actor — check if we have their inbox stored locally
      case Hybridsocial.Repo.get_by(Hybridsocial.Accounts.Identity, ap_actor_url: actor_url) do
        %{inbox_url: inbox} when is_binary(inbox) and inbox != "" ->
          inbox

        _ ->
          # Try remote_actors cache, then fetch from remote server
          fetch_remote_inbox(actor_url)
      end
    end
  end

  defp fetch_remote_inbox(actor_url) do
    # Check the remote_actors cache first
    case Hybridsocial.Repo.get_by(Hybridsocial.Federation.RemoteActor, ap_id: actor_url) do
      nil ->
        # Fetch actor from remote server to get inbox
        Logger.debug("No cached remote actor for #{actor_url}, attempting fetch")

        case fetch_actor_inbox_from_remote(actor_url) do
          nil -> nil
          inbox -> inbox
        end

      remote_actor ->
        remote_actor.inbox_url
    end
  end

  defp fetch_actor_inbox_from_remote(actor_url) do
    case Hybridsocial.Federation.SignedFetch.get(actor_url,
           follow_redirect: true,
           timeout: 10_000
         ) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"inbox" => inbox}} when is_binary(inbox) -> inbox
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp followers_collection?(url, identity) do
    url == "#{HybridsocialWeb.Endpoint.url()}/actors/#{identity.id}/followers"
  end

  defp local_url?(url), do: Hybridsocial.Federation.LocalUrl.local_url?(url)

  defp batch_by_shared_inbox(inbox_urls) do
    # Group inboxes by domain and prefer shared inboxes when available
    inbox_urls
    |> Enum.uniq()
    |> Enum.group_by(fn url ->
      URI.parse(url).host
    end)
    |> Enum.flat_map(fn {_domain, urls} ->
      # If any URL is a shared inbox (no /actors/ or /users/ path), use it for all
      shared =
        Enum.find(urls, fn url ->
          not String.contains?(url, "/actors/") and not String.contains?(url, "/users/")
        end)

      if shared do
        [shared]
      else
        # Use first inbox (they're all on the same domain)
        [hd(urls)]
      end
    end)
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
