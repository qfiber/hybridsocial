defmodule Hybridsocial.Nats.JobConsumer do
  @moduledoc """
  JetStream consumer for background jobs (push notifications, search indexing).
  """

  use GenServer
  require Logger

  alias Hybridsocial.Nats

  @pull_interval 2_000
  @batch_size 5

  @consumers [
    %{stream: "JOBS", name: "push-notifications", handler: :handle_push_notification},
    %{stream: "JOBS", name: "search-indexer", handler: :handle_search_index}
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Process.send_after(self(), :pull, 5_000)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:pull, state) do
    if Nats.connected?() do
      for consumer <- @consumers do
        pull_consumer(consumer)
      end
    end

    Process.send_after(self(), :pull, @pull_interval)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp pull_consumer(%{stream: stream, name: name, handler: handler}) do
    conn = Nats.connection()
    subject = "$JS.API.CONSUMER.MSG.NEXT.#{stream}.#{name}"
    payload = Jason.encode!(%{batch: @batch_size, no_wait: true})

    case Gnat.request(conn, subject, payload, receive_timeout: 3_000) do
      {:ok, %{body: body, headers: headers}} ->
        status = get_status(headers)

        if status != 404 and body != "" do
          case Jason.decode(body) do
            {:ok, data} ->
              result = apply(__MODULE__, handler, [data])
              reply_to = get_reply_to(headers)

              case result do
                :ok -> if reply_to, do: Gnat.pub(conn, reply_to, "+ACK")
                {:error, _} -> if reply_to, do: Gnat.pub(conn, reply_to, "-NAK")
              end

            _ ->
              Logger.warning("JobConsumer: invalid JSON on #{name}")
          end
        end

      {:error, :timeout} ->
        :ok

      {:error, reason} ->
        Logger.debug("JobConsumer pull error for #{name}: #{inspect(reason)}")
    end
  end

  # ---- Job Handlers ----

  def handle_push_notification(%{"user_id" => user_id, "title" => title, "body" => body} = data) do
    try do
      Hybridsocial.Push.Delivery.send_to_user(user_id, %{
        title: title,
        body: body,
        url: data["url"]
      })

      :ok
    rescue
      e ->
        Logger.warning("Push notification job failed: #{inspect(e)}")
        {:error, e}
    end
  end

  def handle_push_notification(_), do: :ok

  def handle_search_index(%{"action" => action, "type" => type} = data) do
    try do
      alias Hybridsocial.Search.Indexer

      case {action, type} do
        {"index", "post"} ->
          if data["id"], do: Indexer.index_post(Hybridsocial.Social.Posts.get_post(data["id"]))

        {"delete", "post"} ->
          if data["id"], do: Indexer.remove_post(data["id"])

        {"index", "identity"} ->
          if data["id"],
            do: Indexer.index_identity(Hybridsocial.Accounts.get_identity(data["id"]))

        {"index", "group"} ->
          if data["id"], do: Indexer.index_group(Hybridsocial.Groups.get_group(data["id"]))

        _ ->
          Logger.debug("Unknown search index job: #{action}/#{type}")
      end

      :ok
    rescue
      e ->
        Logger.warning("Search index job failed: #{inspect(e)}")
        {:error, e}
    end
  end

  def handle_search_index(_), do: :ok

  # ---- Helpers ----

  defp get_status(nil), do: nil

  defp get_status(headers) when is_list(headers) do
    case Enum.find(headers, fn {k, _} -> k == "Status" end) do
      {_, s} -> String.to_integer(String.trim(s))
      nil -> nil
    end
  end

  defp get_status(_), do: nil

  defp get_reply_to(nil), do: nil

  defp get_reply_to(headers) when is_list(headers) do
    case Enum.find(headers, fn {k, _} -> k == "Reply-To" end) do
      {_, r} -> String.trim(r)
      nil -> nil
    end
  end

  defp get_reply_to(_), do: nil
end
