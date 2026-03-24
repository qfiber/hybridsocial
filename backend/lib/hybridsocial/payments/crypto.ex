defmodule Hybridsocial.Payments.Crypto do
  @moduledoc """
  Cryptocurrency payment gateway implementation.

  Designed for BTCPay Server or compatible self-hosted crypto payment
  processors. Communicates via the BTCPay Greenfield API over HTTPoison.
  Configuration is read from `Hybridsocial.Config` at runtime.
  """

  @behaviour Hybridsocial.Payments.Gateway

  require Logger

  # ---------------------------------------------------------------------------
  # Configuration helpers
  # ---------------------------------------------------------------------------

  defp base_url do
    Hybridsocial.Config.get("crypto_payment_url") || System.get_env("CRYPTO_PAYMENT_URL")
  end

  defp api_key do
    Hybridsocial.Config.get("crypto_api_key") || System.get_env("CRYPTO_API_KEY")
  end

  defp store_id do
    Hybridsocial.Config.get("crypto_store_id") || System.get_env("CRYPTO_STORE_ID")
  end

  defp auth_headers do
    [
      {"Authorization", "token #{api_key()}"},
      {"Content-Type", "application/json"}
    ]
  end

  # ---------------------------------------------------------------------------
  # Gateway callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def create_checkout(identity_id, plan, opts) do
    url = "#{base_url()}/api/v1/stores/#{store_id()}/invoices"

    body =
      Jason.encode!(%{
        "metadata" => %{
          "identity_id" => identity_id,
          "plan" => plan
        },
        "checkout" => %{
          "redirectURL" => Map.get(opts, :success_url, ""),
          "redirectAutomatically" => true
        },
        "amount" => Map.get(opts, :amount),
        "currency" => Map.get(opts, :currency, "USD")
      })

    case HTTPoison.post(url, body, auth_headers()) do
      {:ok, %HTTPoison.Response{status_code: 200, body: resp_body}} ->
        case Jason.decode(resp_body) do
          {:ok, %{"id" => invoice_id, "checkoutLink" => checkout_url}} ->
            {:ok, %{session_id: invoice_id, url: checkout_url}}

          {:ok, decoded} ->
            Logger.error("Crypto unexpected checkout response: #{inspect(decoded)}")
            {:error, :unexpected_response}

          {:error, reason} ->
            {:error, {:json_decode_error, reason}}
        end

      {:ok, %HTTPoison.Response{status_code: status, body: resp_body}} ->
        Logger.error("Crypto create_checkout failed (#{status}): #{resp_body}")
        {:error, {:crypto_error, status, resp_body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Crypto HTTP error: #{inspect(reason)}")
        {:error, {:http_error, reason}}
    end
  end

  @impl true
  def verify_payment(invoice_id) do
    url = "#{base_url()}/api/v1/stores/#{store_id()}/invoices/#{invoice_id}"

    case HTTPoison.get(url, auth_headers()) do
      {:ok, %HTTPoison.Response{status_code: 200, body: resp_body}} ->
        case Jason.decode(resp_body) do
          {:ok, %{"status" => status, "amount" => amount, "currency" => currency}} ->
            {:ok,
             %{
               status: String.downcase(status),
               amount: parse_amount(amount),
               currency: String.downcase(currency)
             }}

          {:ok, decoded} ->
            Logger.error("Crypto unexpected verify response: #{inspect(decoded)}")
            {:error, :unexpected_response}

          {:error, reason} ->
            {:error, {:json_decode_error, reason}}
        end

      {:ok, %HTTPoison.Response{status_code: status, body: resp_body}} ->
        Logger.error("Crypto verify_payment failed (#{status}): #{resp_body}")
        {:error, {:crypto_error, status, resp_body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Crypto HTTP error: #{inspect(reason)}")
        {:error, {:http_error, reason}}
    end
  end

  @impl true
  def cancel_subscription(_external_id) do
    # Crypto payments are typically one-time; subscriptions are handled
    # by recurring invoice schedules in BTCPay Server. Cancellation means
    # removing the schedule, which is not yet implemented.
    Logger.warning("Crypto gateway: cancel_subscription is not yet implemented")
    {:error, :not_implemented}
  end

  @impl true
  def handle_webhook(payload, headers) do
    # BTCPay Server signs webhooks with HMAC-SHA256 using the webhook secret.
    webhook_secret =
      Hybridsocial.Config.get("crypto_webhook_secret") ||
        System.get_env("CRYPTO_WEBHOOK_SECRET")

    signature = Map.get(headers, "btcpay-sig", "")

    if is_nil(webhook_secret) || webhook_secret == "" do
      Logger.error("Crypto webhook secret not configured")
      {:error, :webhook_secret_not_configured}
    else
      expected =
        "sha256=" <>
          (:crypto.mac(:hmac, :sha256, webhook_secret, payload)
           |> Base.encode16(case: :lower))

      if Plug.Crypto.secure_compare(expected, signature) do
        case Jason.decode(payload) do
          {:ok, event} -> {:ok, event}
          {:error, reason} -> {:error, {:json_decode_error, reason}}
        end
      else
        {:error, :invalid_signature}
      end
    end
  end

  @impl true
  def refund(invoice_id, opts) do
    url = "#{base_url()}/api/v1/stores/#{store_id()}/invoices/#{invoice_id}/refund"

    body =
      Jason.encode!(%{
        "paymentMethod" => Map.get(opts, :payment_method, "BTC"),
        "description" => Map.get(opts, :reason, "Refund")
      })

    case HTTPoison.post(url, body, auth_headers()) do
      {:ok, %HTTPoison.Response{status_code: 200, body: resp_body}} ->
        case Jason.decode(resp_body) do
          {:ok, refund_data} -> {:ok, refund_data}
          {:error, reason} -> {:error, {:json_decode_error, reason}}
        end

      {:ok, %HTTPoison.Response{status_code: status, body: resp_body}} ->
        Logger.error("Crypto refund failed (#{status}): #{resp_body}")
        {:error, {:crypto_error, status, resp_body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Crypto HTTP error: #{inspect(reason)}")
        {:error, {:http_error, reason}}
    end
  end

  @impl true
  def name, do: "crypto"

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp parse_amount(value) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> round(float * 100)
      :error -> 0
    end
  end

  defp parse_amount(value) when is_number(value), do: round(value * 100)
  defp parse_amount(_), do: 0
end
