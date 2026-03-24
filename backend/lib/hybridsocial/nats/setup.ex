defmodule Hybridsocial.Nats.Setup do
  @moduledoc """
  Creates JetStream streams and consumers on startup.
  Idempotent — safe to run multiple times.
  """

  use GenServer
  require Logger

  @streams [
    %{
      name: "FEDERATION",
      subjects: ["federation.deliver.>"],
      retention: :workqueue,
      max_age: 7 * 24 * 60 * 60 * 1_000_000_000,
      storage: :file,
      description: "Federation activity delivery queue"
    },
    %{
      name: "EVENTS",
      subjects: ["events.>"],
      retention: :limits,
      max_age: 24 * 60 * 60 * 1_000_000_000,
      storage: :memory,
      description: "Real-time events (posts, notifications, deletes)"
    },
    %{
      name: "JOBS",
      subjects: ["jobs.>"],
      retention: :workqueue,
      max_age: 3 * 24 * 60 * 60 * 1_000_000_000,
      storage: :file,
      description: "Background jobs (search indexing, push notifications)"
    }
  ]

  @consumers [
    %{
      stream: "FEDERATION",
      name: "federation-delivery",
      filter_subject: "federation.deliver.>",
      ack_wait: 60 * 1_000_000_000,
      max_deliver: 6,
      description: "Delivers ActivityPub activities to remote inboxes"
    },
    %{
      stream: "JOBS",
      name: "push-notifications",
      filter_subject: "jobs.push_notification",
      ack_wait: 30 * 1_000_000_000,
      max_deliver: 3,
      description: "Delivers web push notifications"
    },
    %{
      stream: "JOBS",
      name: "search-indexer",
      filter_subject: "jobs.search_index",
      ack_wait: 30 * 1_000_000_000,
      max_deliver: 3,
      description: "Indexes content to OpenSearch"
    }
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Wait for NATS connection before setting up
    Process.send_after(self(), :setup, 3_000)
    {:ok, %{setup_complete: false}}
  end

  @impl true
  def handle_info(:setup, state) do
    if Hybridsocial.Nats.connected?() do
      setup_streams()
      setup_consumers()
      Logger.info("JetStream streams and consumers configured")
      {:noreply, %{state | setup_complete: true}}
    else
      Logger.debug("NATS not connected yet, retrying JetStream setup in 5s")
      Process.send_after(self(), :setup, 5_000)
      {:noreply, state}
    end
  end

  defp setup_streams do
    conn = Hybridsocial.Nats.connection()

    for stream_config <- @streams do
      create_stream(conn, stream_config)
    end
  end

  defp setup_consumers do
    conn = Hybridsocial.Nats.connection()

    for consumer_config <- @consumers do
      create_consumer(conn, consumer_config)
    end
  end

  defp create_stream(conn, config) do
    # JetStream API: create or update stream via $JS.API.STREAM.CREATE.<name>
    subject = "$JS.API.STREAM.CREATE.#{config.name}"

    payload = %{
      name: config.name,
      subjects: config.subjects,
      retention: Atom.to_string(config.retention),
      max_age: config.max_age,
      storage: Atom.to_string(config.storage),
      description: config.description,
      num_replicas: 1
    }

    case Gnat.request(conn, subject, Jason.encode!(payload), receive_timeout: 5_000) do
      {:ok, %{body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"error" => %{"err_code" => 10058}}} ->
            # Stream already exists — update it
            update_subject = "$JS.API.STREAM.UPDATE.#{config.name}"
            Gnat.request(conn, update_subject, Jason.encode!(payload), receive_timeout: 5_000)
            Logger.debug("JetStream stream #{config.name} already exists, updated")

          {:ok, %{"error" => error}} ->
            Logger.warning("Failed to create JetStream stream #{config.name}: #{inspect(error)}")

          {:ok, _} ->
            Logger.info("JetStream stream #{config.name} created")
        end

      {:error, reason} ->
        Logger.warning(
          "JetStream stream create request failed for #{config.name}: #{inspect(reason)}"
        )
    end
  end

  defp create_consumer(conn, config) do
    subject = "$JS.API.CONSUMER.CREATE.#{config.stream}.#{config.name}"

    payload = %{
      stream_name: config.stream,
      config: %{
        durable_name: config.name,
        filter_subject: config.filter_subject,
        ack_policy: "explicit",
        ack_wait: config.ack_wait,
        max_deliver: config.max_deliver,
        deliver_policy: "all",
        description: config.description
      }
    }

    case Gnat.request(conn, subject, Jason.encode!(payload), receive_timeout: 5_000) do
      {:ok, %{body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"error" => _}} ->
            Logger.debug("JetStream consumer #{config.name} may already exist")

          {:ok, _} ->
            Logger.info("JetStream consumer #{config.name} created on #{config.stream}")
        end

      {:error, reason} ->
        Logger.warning("JetStream consumer create failed for #{config.name}: #{inspect(reason)}")
    end
  end
end
