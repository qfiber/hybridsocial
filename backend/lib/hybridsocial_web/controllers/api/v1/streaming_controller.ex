defmodule HybridsocialWeb.Api.V1.StreamingController do
  @moduledoc """
  SSE streaming controller for real-time updates.

  Uses chunked transfer encoding to stream Server-Sent Events (SSE) to clients.
  """
  use HybridsocialWeb, :controller

  @doc """
  Streams user-specific events: notifications, home timeline updates, DM notifications.
  Requires authentication.
  """
  def user(conn, _params) do
    identity = conn.assigns.current_identity

    conn = start_sse(conn)

    Phoenix.PubSub.subscribe(Hybridsocial.PubSub, "user:#{identity.id}")

    listen_loop(conn)
  end

  @doc """
  Streams public timeline updates. Authentication optional.
  """
  def public(conn, _params) do
    conn = start_sse(conn)

    Phoenix.PubSub.subscribe(Hybridsocial.PubSub, "timeline:public")

    listen_loop(conn)
  end

  @doc """
  Streams posts with a specific hashtag. Authentication optional.
  """
  def hashtag(conn, %{"tag" => tag}) do
    conn = start_sse(conn)

    Phoenix.PubSub.subscribe(Hybridsocial.PubSub, "hashtag:#{tag}")

    listen_loop(conn)
  end

  @doc """
  Streams posts from list members. Requires authentication.
  """
  def list(conn, %{"id" => list_id}) do
    conn = start_sse(conn)

    Phoenix.PubSub.subscribe(Hybridsocial.PubSub, "list:#{list_id}")

    listen_loop(conn)
  end

  @doc """
  Streams new group posts. Requires authentication.
  """
  def group(conn, %{"id" => group_id}) do
    conn = start_sse(conn)

    Phoenix.PubSub.subscribe(Hybridsocial.PubSub, "group:#{group_id}")

    listen_loop(conn)
  end

  defp start_sse(conn) do
    conn
    |> put_resp_content_type("text/event-stream")
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_header("x-accel-buffering", "no")
    |> send_chunked(200)
  end

  defp listen_loop(conn) do
    receive do
      %{event: event, payload: payload} ->
        data = if is_binary(payload), do: payload, else: Jason.encode!(payload)

        case Plug.Conn.chunk(conn, "event: #{event}\ndata: #{data}\n\n") do
          {:ok, conn} ->
            listen_loop(conn)

          {:error, :closed} ->
            conn
        end

      :heartbeat ->
        case Plug.Conn.chunk(conn, ":heartbeat\n\n") do
          {:ok, conn} ->
            listen_loop(conn)

          {:error, :closed} ->
            conn
        end
    after
      30_000 ->
        # Send a heartbeat comment every 30 seconds to keep connection alive
        case Plug.Conn.chunk(conn, ":heartbeat\n\n") do
          {:ok, conn} ->
            listen_loop(conn)

          {:error, :closed} ->
            conn
        end
    end
  end
end
