defmodule Hybridsocial.Streaming.NatsBridge do
  @moduledoc """
  Bridges NATS events to local Phoenix.PubSub.
  Subscribes to NATS event subjects and rebroadcasts them to local PubSub
  so SSE connections on this node receive updates from all nodes.
  """

  use GenServer
  require Logger

  alias Phoenix.PubSub

  @pubsub Hybridsocial.PubSub
  @subscribe_subjects [
    "events.timeline.>",
    "events.user.>",
    "events.group.>",
    "events.hashtag.>",
    "events.direct.>"
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Process.send_after(self(), :subscribe, 5_000)
    {:ok, %{subscriptions: []}}
  end

  @impl true
  def handle_info(:subscribe, state) do
    if Hybridsocial.Nats.connected?() do
      subs =
        Enum.map(@subscribe_subjects, fn subject ->
          case Hybridsocial.Nats.subscribe(subject) do
            {:ok, sid} ->
              Logger.debug("NATS bridge subscribed to #{subject}")
              {subject, sid}

            {:error, reason} ->
              Logger.warning("NATS bridge subscribe failed for #{subject}: #{inspect(reason)}")
              nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      {:noreply, %{state | subscriptions: subs}}
    else
      Process.send_after(self(), :subscribe, 5_000)
      {:noreply, state}
    end
  end

  # Handle NATS messages and rebroadcast to local PubSub
  @impl true
  def handle_info({:msg, %{topic: topic, body: body}}, state) do
    case Jason.decode(body) do
      {:ok, event} ->
        pubsub_topic = nats_to_pubsub_topic(topic)

        if pubsub_topic do
          PubSub.broadcast(@pubsub, pubsub_topic, event)
        end

      {:error, _} ->
        Logger.debug("NATS bridge: invalid JSON on #{topic}")
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # Map NATS subjects to Phoenix.PubSub topics
  # events.timeline.public → timeline:public
  # events.user.abc123 → user:abc123
  # events.group.abc123 → group:abc123
  # events.hashtag.elixir → hashtag:elixir
  # events.direct.abc123 → direct:abc123
  defp nats_to_pubsub_topic(nats_subject) do
    case String.split(nats_subject, ".", parts: 3) do
      ["events", category, id] -> "#{category}:#{id}"
      _ -> nil
    end
  end
end
