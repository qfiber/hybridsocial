defmodule Hybridsocial.Notifications.Delivery.Push do
  @moduledoc """
  Push notification delivery channel.

  Wraps `Hybridsocial.Push.Delivery` to conform to the
  `Hybridsocial.Notifications.Delivery` behaviour.
  """

  @behaviour Hybridsocial.Notifications.Delivery

  require Logger

  @impl true
  def deliver(recipient_id, payload, _opts) do
    case Hybridsocial.Push.Delivery.send_to_user(recipient_id, payload) do
      {:ok, _count} -> :ok
      error -> {:error, error}
    end
  end

  @impl true
  def channel_name, do: :push

  @impl true
  def available? do
    vapid_key = Hybridsocial.Config.get("vapid_public_key")
    vapid_key != nil and vapid_key != ""
  end
end
