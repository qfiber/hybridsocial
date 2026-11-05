defmodule Hybridsocial.Federation do
  @moduledoc """
  The Federation context. Manages remote actors, instance policies,
  delivery tracking, and deduplication for ActivityPub federation.
  """

  import Ecto.Query
  alias Hybridsocial.Repo
  alias Hybridsocial.Federation.{RemoteActor, InstancePolicy, Delivery, Dedup}

  # How long before we re-fetch a remote actor (24 hours)
  @stale_after_seconds 86_400

  @doc """
  Spawn a fire-and-forget ActivityPub delivery task on the
  `DeliveryTaskSupervisor`, unless federation delivery is disabled.

  In the test env (`federation_delivery_enabled: false`) this no-ops:
  the delivery closures do `Repo` work and outlive the test, so once the
  test checks its SQL-sandbox connection back in they crash with a
  `DBConnection.OwnershipError`. Tests that specifically exercise
  delivery flip the flag on. Defaults to enabled, so prod is unchanged.

  Returns `:ok` when disabled so callers stay fire-and-forget.
  """
  def deliver_async(fun) when is_function(fun, 0) do
    if delivery_enabled?() do
      Task.Supervisor.start_child(Hybridsocial.Federation.DeliveryTaskSupervisor, fun)
    else
      :ok
    end
  end

  @doc "Whether async federation delivery should actually run (off in tests)."
  def delivery_enabled?,
    do: Application.get_env(:hybridsocial, :federation_delivery_enabled, true)

  # --- Remote Actor Cache ---

  @doc """
  Gets a remote actor from cache, fetching via HTTP if stale or missing.
  """
  def get_or_fetch_remote_actor(ap_id) do
    case Repo.get_by(RemoteActor, ap_id: ap_id) do
      nil ->
        fetch_and_cache_remote_actor(ap_id)

      actor ->
        if stale?(actor) do
          fetch_and_cache_remote_actor(ap_id)
        else
          {:ok, actor}
        end
    end
  end

  @doc """
  Upserts a remote actor into the cache.
  """
  def cache_remote_actor(actor_data) do
    attrs =
      actor_data
      |> Map.put(:last_fetched_at, DateTime.utc_now())

    %RemoteActor{}
    |> RemoteActor.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: :ap_id,
      returning: true
    )
  end

  defp stale?(%RemoteActor{last_fetched_at: nil}), do: true

  defp stale?(%RemoteActor{last_fetched_at: fetched_at}) do
    DateTime.diff(DateTime.utc_now(), fetched_at) > @stale_after_seconds
  end

  defp fetch_and_cache_remote_actor(ap_id) do
    headers = [{"Accept", "application/activity+json"}]

    case Hybridsocial.HTTP.get(ap_id, headers) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} ->
            actor_attrs = %{
              ap_id: data["id"],
              handle: data["preferredUsername"],
              domain: URI.parse(data["id"]).host,
              display_name: data["name"],
              public_key: get_in(data, ["publicKey", "publicKeyPem"]),
              inbox_url: data["inbox"],
              outbox_url: data["outbox"],
              followers_url: data["followers"],
              shared_inbox_url: get_in(data, ["endpoints", "sharedInbox"]),
              avatar_url: get_in(data, ["icon", "url"])
            }

            cache_remote_actor(actor_attrs)

          {:error, _} ->
            {:error, :invalid_response}
        end

      {:ok, %{status_code: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # --- Instance Policies ---

  @doc "Returns the policy for a domain, or nil."
  def get_instance_policy(domain) do
    Repo.get(InstancePolicy, domain)
  end

  @doc "Creates or updates a policy for a domain."
  def set_instance_policy(domain, policy, reason, admin_id) do
    attrs = %{domain: domain, policy: policy, reason: reason, created_by: admin_id}

    # Don't preset `domain` on the struct: cast sees an unchanged value and
    # records no change, which would skip normalizing and validating it.
    %InstancePolicy{}
    |> InstancePolicy.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:policy, :reason, :created_by, :updated_at]},
      conflict_target: :domain,
      returning: true
    )
  end

  @doc "Removes a policy for a domain."
  def delete_instance_policy(domain) do
    case Repo.get(InstancePolicy, domain) do
      nil -> {:error, :not_found}
      policy -> Repo.delete(policy)
    end
  end

  @doc "Lists all instance policies."
  def list_instance_policies do
    InstancePolicy
    |> order_by([p], asc: p.domain)
    |> Repo.all()
  end

  @doc "Returns true if the domain is not suspended."
  def domain_allowed?(domain) do
    case get_instance_policy(String.downcase(domain)) do
      nil -> true
      %InstancePolicy{policy: "suspend"} -> false
      _ -> true
    end
  end

  # --- Delivery Tracking ---

  @doc "Records a new delivery attempt."
  def record_delivery(attrs) do
    %Delivery{}
    |> Delivery.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates an existing delivery record."
  def update_delivery(id, attrs) do
    case Repo.get(Delivery, id) do
      nil -> {:error, :not_found}
      delivery -> delivery |> Delivery.changeset(attrs) |> Repo.update()
    end
  end

  # --- Deduplication ---

  @doc "Returns true if the activity hash has already been processed."
  def deduplicate?(activity_hash) do
    Repo.exists?(from d in Dedup, where: d.activity_hash == ^activity_hash)
  end

  @doc "Records a dedup entry."
  def record_dedup(activity_hash, activity_id) do
    now = DateTime.utc_now()
    expires_at = DateTime.add(now, 7 * 86_400, :second)

    %Dedup{}
    |> Dedup.changeset(%{
      activity_hash: activity_hash,
      activity_id: activity_id,
      processed_at: now,
      expires_at: expires_at
    })
    |> Repo.insert(on_conflict: :nothing)
  end

  @doc "Removes expired dedup entries."
  def cleanup_expired_dedup do
    now = DateTime.utc_now()

    {count, _} =
      from(d in Dedup, where: d.expires_at < ^now)
      |> Repo.delete_all()

    {:ok, count}
  end
end
