defmodule Hybridsocial.Federation.Relays do
  @moduledoc """
  Context for managing ActivityPub relay subscriptions.
  Relays broadcast content to and from other instances.
  """
  import Ecto.Query

  alias Hybridsocial.Repo
  alias Hybridsocial.Federation.Relay

  @doc """
  Subscribes to a relay by sending an AP Follow to the relay inbox.
  Creates a relay record with status "pending".
  """
  def subscribe_to_relay(inbox_url, _admin_id) do
    %Relay{}
    |> Relay.changeset(%{inbox_url: inbox_url, status: "pending"})
    |> Repo.insert()
  end

  @doc """
  Unsubscribes from a relay. Soft-deletes the relay record.
  In production, would also send an Undo{Follow} to the relay inbox.
  """
  def unsubscribe_from_relay(relay_id, _admin_id) do
    case Repo.get(Relay, relay_id) do
      nil ->
        {:error, :not_found}

      relay ->
        Repo.delete(relay)
    end
  end

  @doc """
  Lists all relays.
  """
  def list_relays do
    Relay
    |> order_by([r], desc: r.inserted_at)
    |> Repo.all()
  end

  @doc """
  Marks a relay as accepted. Called when we receive an Accept activity
  from the relay in response to our Follow.
  """
  def accept_relay(domain) do
    relay =
      Relay
      |> where([r], fragment("? LIKE '%' || ? || '%'", r.inbox_url, ^domain))
      |> Repo.one()

    case relay do
      nil ->
        {:error, :not_found}

      relay ->
        relay
        |> Relay.changeset(%{status: "accepted"})
        |> Repo.update()
    end
  end

  @doc """
  Processes an Announce activity from a relay.
  In a full implementation, this would fetch and re-index the announced post.
  For now, returns :ok as a stub.
  """
  def process_relay_announce(_activity) do
    :ok
  end

  @doc """
  Gets a relay by ID.
  """
  def get_relay(id) do
    Repo.get(Relay, id)
  end
end
