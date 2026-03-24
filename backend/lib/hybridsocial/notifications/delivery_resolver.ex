defmodule Hybridsocial.Notifications.DeliveryResolver do
  @moduledoc """
  Resolves which notification delivery channels are enabled and available.

  Reads the `notification_channels` setting from `Hybridsocial.Config` (a
  comma-separated list of channel names) and returns only the modules that
  report themselves as available at runtime.
  """

  require Logger

  @doc "Returns a list of delivery modules that are both enabled and available."
  @spec enabled_channels() :: [module()]
  def enabled_channels do
    channels = Hybridsocial.Config.get("notification_channels", "push")

    channels
    |> to_string()
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&channel_module/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(& &1.available?())
  end

  defp channel_module("push"), do: Hybridsocial.Notifications.Delivery.Push
  defp channel_module("email"), do: Hybridsocial.Notifications.Delivery.Email
  defp channel_module("sms"), do: Hybridsocial.Notifications.Delivery.Sms
  defp channel_module("noop"), do: Hybridsocial.Notifications.Delivery.Noop

  defp channel_module(unknown) do
    Logger.warning("Unknown notification channel: #{inspect(unknown)}")
    nil
  end
end
