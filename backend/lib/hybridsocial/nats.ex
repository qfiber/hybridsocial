defmodule Hybridsocial.Nats do
  @moduledoc """
  NATS connection manager. Provides convenience functions for publishing
  messages to NATS core and JetStream subjects.
  Falls back gracefully when NATS is unavailable.
  """

  use GenServer
  require Logger

  @connection_name :hybridsocial_nats
  @reconnect_interval 5_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # ---- Client API ----

  @doc "Get the connection name for direct Gnat calls."
  def connection, do: @connection_name

  @doc "Whether NATS is connected and available."
  def connected? do
    case GenServer.call(__MODULE__, :status) do
      :connected -> true
      _ -> false
    end
  end

  @doc "Publish a message to a NATS subject (core NATS, no persistence)."
  def publish(subject, data) when is_binary(subject) do
    payload = encode(data)

    if connected?() do
      case Gnat.pub(@connection_name, subject, payload) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning("NATS publish failed on #{subject}: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:error, :not_connected}
    end
  end

  @doc "Publish a message to a JetStream stream subject (persistent)."
  def js_publish(subject, data) when is_binary(subject) do
    payload = encode(data)

    if connected?() do
      case Gnat.pub(@connection_name, subject, payload) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning("NATS JetStream publish failed on #{subject}: #{inspect(reason)}")
          {:error, reason}
      end
    else
      Logger.warning("NATS not connected, cannot publish to #{subject}")
      {:error, :not_connected}
    end
  end

  @doc "Subscribe to a NATS subject. Messages sent as {:msg, %{topic: ..., body: ...}} to caller."
  def subscribe(subject) do
    if connected?() do
      Gnat.sub(@connection_name, self(), subject)
    else
      {:error, :not_connected}
    end
  end

  # ---- Server Callbacks ----

  @impl true
  def init(_opts) do
    # Start connection attempt asynchronously
    send(self(), :connect)
    {:ok, %{status: :disconnected, pid: nil}}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, state.status, state}
  end

  @impl true
  def handle_info(:connect, _state) do
    nats_url = Application.get_env(:hybridsocial, :nats_url, "nats://localhost:4222")
    uri = URI.parse(nats_url)
    host = uri.host || "localhost"
    port = uri.port || 4222

    connection_settings = %{
      host: to_charlist(host),
      port: port
    }

    case Gnat.start_link(connection_settings, name: @connection_name) do
      {:ok, pid} ->
        Process.monitor(pid)
        Logger.info("NATS connected to #{host}:#{port}")
        {:noreply, %{status: :connected, pid: pid}}

      {:error, reason} ->
        Logger.warning(
          "NATS connection failed: #{inspect(reason)}, retrying in #{@reconnect_interval}ms"
        )

        Process.send_after(self(), :connect, @reconnect_interval)
        {:noreply, %{status: :disconnected, pid: nil}}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, %{pid: pid} = state) do
    Logger.warning("NATS connection lost: #{inspect(reason)}, reconnecting...")
    Process.send_after(self(), :connect, @reconnect_interval)
    {:noreply, %{state | status: :disconnected, pid: nil}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---- Helpers ----

  defp encode(data) when is_binary(data), do: data
  defp encode(data), do: Jason.encode!(data)
end
