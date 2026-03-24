defmodule Hybridsocial.Federation.NatsDeliveryConsumer do
  @moduledoc """
  JetStream pull consumer for federation activity delivery.
  Replaces the DB-polling DeliveryWorker with NATS-based reliable delivery.
  """

  use GenServer
  require Logger

  alias Hybridsocial.Federation.Publisher
  alias Hybridsocial.Nats

  @pull_interval 1_000
  @batch_size 10
  @consumer_stream "FEDERATION"
  @consumer_name "federation-delivery"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Process.send_after(self(), :pull, 5_000)
    {:ok, %{active: false}}
  end

  @impl true
  def handle_info(:pull, state) do
    if Nats.connected?() do
      pull_and_process()
    end

    Process.send_after(self(), :pull, @pull_interval)
    {:noreply, %{state | active: Nats.connected?()}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp pull_and_process do
    conn = Nats.connection()

    # JetStream pull request
    subject = "$JS.API.CONSUMER.MSG.NEXT.#{@consumer_stream}.#{@consumer_name}"
    payload = Jason.encode!(%{batch: @batch_size, no_wait: true})

    case Gnat.request(conn, subject, payload, receive_timeout: 5_000) do
      {:ok, %{body: body, headers: headers}} ->
        # Check if this is a "no messages" response
        status = get_nats_status(headers)

        if status != 404 and body != "" do
          process_message(conn, body, headers)
        end

      {:error, :timeout} ->
        # No messages available, that's fine
        :ok

      {:error, reason} ->
        Logger.debug("Federation consumer pull error: #{inspect(reason)}")
    end
  end

  defp process_message(conn, body, headers) do
    case Jason.decode(body) do
      {:ok, %{"inbox_url" => inbox_url, "body" => activity_body, "actor_id" => actor_id} = msg} ->
        identity = Hybridsocial.Accounts.get_identity(actor_id)

        result =
          if identity do
            Publisher.deliver_to_inbox(inbox_url, activity_body, identity)
          else
            {:error, "Actor not found: #{actor_id}"}
          end

        reply_to = get_reply_to(headers)

        case result do
          {:ok, _status} ->
            # ACK — successfully delivered
            if reply_to, do: Gnat.pub(conn, reply_to, "+ACK")
            Logger.debug("Federation delivery to #{inbox_url}: success")

            # Update delivery record if tracking
            if msg["delivery_id"] do
              update_delivery_status(msg["delivery_id"], "delivered")
            end

          {:error, reason} ->
            # NAK — request redelivery with delay
            if reply_to, do: Gnat.pub(conn, reply_to, "-NAK")
            Logger.warning("Federation delivery to #{inbox_url} failed: #{inspect(reason)}")

            if msg["delivery_id"] do
              update_delivery_status(msg["delivery_id"], "retrying", reason)
            end
        end

      {:error, _} ->
        Logger.warning("Federation consumer: invalid message payload")
    end
  end

  defp get_nats_status(nil), do: nil

  defp get_nats_status(headers) when is_list(headers) do
    case Enum.find(headers, fn {k, _} -> k == "Status" end) do
      {_, status} -> String.to_integer(String.trim(status))
      nil -> nil
    end
  end

  defp get_nats_status(_), do: nil

  defp get_reply_to(nil), do: nil

  defp get_reply_to(headers) when is_list(headers) do
    case Enum.find(headers, fn {k, _} -> k == "Reply-To" end) do
      {_, reply} -> String.trim(reply)
      nil -> nil
    end
  end

  defp get_reply_to(_), do: nil

  defp update_delivery_status(delivery_id, status, error \\ nil) do
    import Ecto.Query
    alias Hybridsocial.Repo

    updates = [status: status, last_attempt_at: DateTime.utc_now()]
    updates = if error, do: [{:error, to_string(error)} | updates], else: updates

    from(d in "federation_deliveries", where: d.id == type(^delivery_id, Ecto.UUID))
    |> Repo.update_all(set: updates)
  rescue
    _ -> :ok
  end
end
