defmodule Hybridsocial.Notifications.Delivery.Noop do
  @moduledoc """
  No-op notification delivery channel for testing.

  Always reports as available and silently discards all notifications.
  """

  @behaviour Hybridsocial.Notifications.Delivery

  require Logger

  @impl true
  def deliver(_recipient_id, _payload, _opts), do: :ok

  @impl true
  def channel_name, do: :noop

  @impl true
  def available?, do: true
end
