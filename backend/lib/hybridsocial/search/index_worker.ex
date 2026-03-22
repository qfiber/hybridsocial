defmodule Hybridsocial.Search.IndexWorker do
  @moduledoc """
  GenServer that subscribes to PubSub events and indexes/removes
  documents in OpenSearch asynchronously.
  """

  use GenServer

  require Logger

  alias Hybridsocial.Search.Indexer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(Hybridsocial.PubSub, "posts")
    Phoenix.PubSub.subscribe(Hybridsocial.PubSub, "identities")
    Phoenix.PubSub.subscribe(Hybridsocial.PubSub, "groups")
    {:ok, %{}}
  end

  # --- Post events ---

  @impl true
  def handle_info({:post_created, post}, state) do
    Task.start(fn -> Indexer.index_post(post) end)
    {:noreply, state}
  end

  @impl true
  def handle_info({:post_updated, post}, state) do
    Task.start(fn -> Indexer.index_post(post) end)
    {:noreply, state}
  end

  @impl true
  def handle_info({:post_deleted, post_id}, state) do
    Task.start(fn -> Indexer.remove_post(post_id) end)
    {:noreply, state}
  end

  # --- Identity events ---

  @impl true
  def handle_info({:identity_created, identity}, state) do
    Task.start(fn -> Indexer.index_identity(identity) end)
    {:noreply, state}
  end

  @impl true
  def handle_info({:identity_updated, identity}, state) do
    Task.start(fn -> Indexer.index_identity(identity) end)
    {:noreply, state}
  end

  @impl true
  def handle_info({:identity_deleted, identity_id}, state) do
    Task.start(fn -> Indexer.remove_identity(identity_id) end)
    {:noreply, state}
  end

  # --- Group events ---

  @impl true
  def handle_info({:group_created, group}, state) do
    Task.start(fn -> Indexer.index_group(group) end)
    {:noreply, state}
  end

  @impl true
  def handle_info({:group_updated, group}, state) do
    Task.start(fn -> Indexer.index_group(group) end)
    {:noreply, state}
  end

  @impl true
  def handle_info({:group_deleted, group_id}, state) do
    Task.start(fn -> Indexer.remove_group(group_id) end)
    {:noreply, state}
  end

  # Catch-all for unhandled messages
  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
