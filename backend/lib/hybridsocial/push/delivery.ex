defmodule Hybridsocial.Push.Delivery do
  @moduledoc """
  Delivers Web Push notifications to subscribed browsers/devices.
  """
  import Ecto.Query
  alias Hybridsocial.Repo
  alias Hybridsocial.Push.{Subscription, Vapid, WebPush}

  require Logger

  @doc "Send push notification to all subscriptions for an identity"
  def send_to_user(identity_id, payload) when is_map(payload) do
    subscriptions =
      Repo.all(from s in Subscription, where: s.identity_id == ^identity_id)

    json = Jason.encode!(payload)

    Enum.each(subscriptions, fn sub ->
      Task.start(fn ->
        send_push(sub, json)
      end)
    end)

    {:ok, length(subscriptions)}
  end

  defp send_push(subscription, payload) do
    sub = %{
      endpoint: subscription.endpoint,
      keys: %{
        p256dh: subscription.key_p256dh,
        auth: subscription.key_auth
      }
    }

    vapid = %{
      subject: "mailto:#{Hybridsocial.Config.get("contact_email", "admin@localhost")}",
      public_key: Vapid.public_key(),
      private_key: Vapid.private_key()
    }

    case WebPush.send_web_push(payload, sub, vapid) do
      {:ok, %{status_code: status}} when status in 200..299 ->
        :ok

      {:ok, %{status_code: 404}} ->
        Repo.delete(subscription)
        :expired

      {:ok, %{status_code: 410}} ->
        Repo.delete(subscription)
        :expired

      error ->
        Logger.warning("Push delivery failed: #{inspect(error)}")
        :error
    end
  end
end
