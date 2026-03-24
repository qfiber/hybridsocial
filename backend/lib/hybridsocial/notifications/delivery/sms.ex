defmodule Hybridsocial.Notifications.Delivery.Sms do
  @moduledoc """
  SMS notification delivery channel.

  Sends SMS messages via a configurable HTTP-based provider (Twilio-style API).
  Requires `sms_provider_url`, `sms_api_key`, and `sms_from_number` to be set
  in `Hybridsocial.Config`.
  """

  @behaviour Hybridsocial.Notifications.Delivery

  alias Hybridsocial.Repo
  alias Hybridsocial.Accounts.Identity

  require Logger

  @impl true
  def deliver(recipient_id, payload, _opts) do
    case fetch_recipient_phone(recipient_id) do
      {:ok, phone_number} ->
        send_sms(phone_number, "#{payload.title}\n#{payload.body}")

      {:error, reason} ->
        Logger.debug("Skipping SMS notification: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def channel_name, do: :sms

  @impl true
  def available? do
    url = Hybridsocial.Config.get("sms_provider_url")
    url != nil and url != ""
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp fetch_recipient_phone(recipient_id) do
    identity =
      Identity
      |> Repo.get(recipient_id)
      |> Repo.preload(:user)

    with %Identity{user: user} when not is_nil(user) <- identity,
         phone when is_binary(phone) and phone != "" <- Map.get(user, :phone) do
      {:ok, phone}
    else
      _ -> {:error, :no_phone}
    end
  end

  defp send_sms(to, body) do
    url = Hybridsocial.Config.get("sms_provider_url")
    api_key = Hybridsocial.Config.get("sms_api_key", "")
    from_number = Hybridsocial.Config.get("sms_from_number", "")

    headers = [
      {"Content-Type", "application/json"},
      {"Authorization", "Bearer #{api_key}"}
    ]

    request_body =
      Jason.encode!(%{
        to: to,
        from: from_number,
        body: body
      })

    case HTTPoison.post(url, request_body, headers, recv_timeout: 10_000, timeout: 10_000) do
      {:ok, %{status_code: status}} when status in 200..299 ->
        :ok

      {:ok, %{status_code: status, body: resp_body}} ->
        Logger.warning("SMS delivery failed with status #{status}: #{inspect(resp_body)}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.warning("SMS delivery failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
