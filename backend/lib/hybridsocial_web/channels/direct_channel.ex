defmodule HybridsocialWeb.DirectChannel do
  @moduledoc """
  Channel for direct message real-time communication.
  Handles typing indicators and read receipts.
  """
  use HybridsocialWeb, :channel

  @impl true
  def join("direct:" <> conversation_id, _payload, socket) do
    identity_id = socket.assigns.identity_id

    # Store the conversation_id in socket assigns for later use
    socket = assign(socket, :conversation_id, conversation_id)
    socket = assign(socket, :identity_id, identity_id)

    {:ok, socket}
  end

  @impl true
  def handle_in("typing", _payload, socket) do
    broadcast_from!(socket, "typing", %{
      identity_id: socket.assigns.identity_id
    })

    {:noreply, socket}
  end

  @impl true
  def handle_in("read", _payload, socket) do
    broadcast!(socket, "read", %{
      identity_id: socket.assigns.identity_id,
      conversation_id: socket.assigns.conversation_id
    })

    {:noreply, socket}
  end
end
