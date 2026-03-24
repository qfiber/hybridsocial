defmodule Hybridsocial.Payments.Paypal do
  @moduledoc """
  PayPal payment gateway implementation.

  Communicates with the PayPal REST API (v2) using HTTPoison. Supports both
  sandbox and live modes, configurable at runtime through the `paypal_mode`
  setting.
  """

  @behaviour Hybridsocial.Payments.Gateway

  require Logger

  @sandbox_url "https://api-m.sandbox.paypal.com"
  @live_url "https://api-m.paypal.com"

  # ---------------------------------------------------------------------------
  # Configuration helpers
  # ---------------------------------------------------------------------------

  defp client_id do
    Hybridsocial.Config.get("paypal_client_id") || System.get_env("PAYPAL_CLIENT_ID")
  end

  defp client_secret do
    Hybridsocial.Config.get("paypal_secret") || System.get_env("PAYPAL_SECRET")
  end

  defp base_url do
    case Hybridsocial.Config.get("paypal_mode", "sandbox") do
      "live" -> @live_url
      _ -> @sandbox_url
    end
  end

  defp get_access_token do
    url = "#{base_url()}/v1/oauth2/token"
    body = "grant_type=client_credentials"

    auth = Base.encode64("#{client_id()}:#{client_secret()}")

    headers = [
      {"Authorization", "Basic #{auth}"},
      {"Content-Type", "application/x-www-form-urlencoded"}
    ]

    case HTTPoison.post(url, body, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: resp_body}} ->
        case Jason.decode(resp_body) do
          {:ok, %{"access_token" => token}} -> {:ok, token}
          {:error, reason} -> {:error, {:json_decode_error, reason}}
        end

      {:ok, %HTTPoison.Response{status_code: status, body: resp_body}} ->
        Logger.error("PayPal token exchange failed (#{status}): #{resp_body}")
        {:error, {:paypal_error, status, resp_body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("PayPal HTTP error during token exchange: #{inspect(reason)}")
        {:error, {:http_error, reason}}
    end
  end

  defp auth_headers(token) do
    [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/json"}
    ]
  end

  # ---------------------------------------------------------------------------
  # Gateway callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def create_checkout(identity_id, plan, opts) do
    with {:ok, token} <- get_access_token() do
      return_url = Map.get(opts, :success_url, "")
      cancel_url = Map.get(opts, :cancel_url, "")

      body =
        Jason.encode!(%{
          "intent" => "SUBSCRIPTION",
          "plan_id" => plan,
          "custom_id" => identity_id,
          "application_context" => %{
            "return_url" => return_url,
            "cancel_url" => cancel_url
          }
        })

      url = "#{base_url()}/v1/billing/subscriptions"

      case HTTPoison.post(url, body, auth_headers(token)) do
        {:ok, %HTTPoison.Response{status_code: status, body: resp_body}}
        when status in [200, 201] ->
          case Jason.decode(resp_body) do
            {:ok, %{"id" => sub_id, "links" => links}} ->
              approve_url =
                links
                |> Enum.find(%{}, &(&1["rel"] == "approve"))
                |> Map.get("href", "")

              {:ok, %{session_id: sub_id, url: approve_url}}

            {:ok, decoded} ->
              Logger.error("PayPal unexpected checkout response: #{inspect(decoded)}")
              {:error, :unexpected_response}

            {:error, reason} ->
              {:error, {:json_decode_error, reason}}
          end

        {:ok, %HTTPoison.Response{status_code: status, body: resp_body}} ->
          Logger.error("PayPal create_checkout failed (#{status}): #{resp_body}")
          {:error, {:paypal_error, status, resp_body}}

        {:error, %HTTPoison.Error{reason: reason}} ->
          Logger.error("PayPal HTTP error: #{inspect(reason)}")
          {:error, {:http_error, reason}}
      end
    end
  end

  @impl true
  def verify_payment(order_id) do
    with {:ok, token} <- get_access_token() do
      url = "#{base_url()}/v2/checkout/orders/#{order_id}"

      case HTTPoison.get(url, auth_headers(token)) do
        {:ok, %HTTPoison.Response{status_code: 200, body: resp_body}} ->
          case Jason.decode(resp_body) do
            {:ok, %{"status" => status, "purchase_units" => [unit | _]}} ->
              amount = get_in(unit, ["amount", "value"]) || "0"
              currency = get_in(unit, ["amount", "currency_code"]) || "USD"

              {:ok,
               %{
                 status: String.downcase(status),
                 amount: parse_amount(amount),
                 currency: String.downcase(currency)
               }}

            {:ok, decoded} ->
              Logger.error("PayPal unexpected verify response: #{inspect(decoded)}")
              {:error, :unexpected_response}

            {:error, reason} ->
              {:error, {:json_decode_error, reason}}
          end

        {:ok, %HTTPoison.Response{status_code: status, body: resp_body}} ->
          Logger.error("PayPal verify_payment failed (#{status}): #{resp_body}")
          {:error, {:paypal_error, status, resp_body}}

        {:error, %HTTPoison.Error{reason: reason}} ->
          Logger.error("PayPal HTTP error: #{inspect(reason)}")
          {:error, {:http_error, reason}}
      end
    end
  end

  @impl true
  def cancel_subscription(subscription_id) do
    with {:ok, token} <- get_access_token() do
      url = "#{base_url()}/v1/billing/subscriptions/#{subscription_id}/cancel"
      body = Jason.encode!(%{"reason" => "Cancelled by user"})

      case HTTPoison.post(url, body, auth_headers(token)) do
        {:ok, %HTTPoison.Response{status_code: 204}} ->
          :ok

        {:ok, %HTTPoison.Response{status_code: status, body: resp_body}} ->
          Logger.error("PayPal cancel_subscription failed (#{status}): #{resp_body}")
          {:error, {:paypal_error, status, resp_body}}

        {:error, %HTTPoison.Error{reason: reason}} ->
          Logger.error("PayPal HTTP error: #{inspect(reason)}")
          {:error, {:http_error, reason}}
      end
    end
  end

  @impl true
  def handle_webhook(payload, headers) do
    # PayPal webhooks use a different verification model. The recommended
    # approach is to call the PayPal Webhook Verification API with the
    # transmission headers. For now we decode and return the event; a
    # production deployment should add full signature verification.
    webhook_id = Hybridsocial.Config.get("paypal_webhook_id")

    with {:ok, token} <- get_access_token() do
      verify_body =
        Jason.encode!(%{
          "auth_algo" => Map.get(headers, "paypal-auth-algo", ""),
          "cert_url" => Map.get(headers, "paypal-cert-url", ""),
          "transmission_id" => Map.get(headers, "paypal-transmission-id", ""),
          "transmission_sig" => Map.get(headers, "paypal-transmission-sig", ""),
          "transmission_time" => Map.get(headers, "paypal-transmission-time", ""),
          "webhook_id" => webhook_id,
          "webhook_event" => Jason.decode!(payload)
        })

      url = "#{base_url()}/v1/notifications/verify-webhook-signature"

      case HTTPoison.post(url, verify_body, auth_headers(token)) do
        {:ok, %HTTPoison.Response{status_code: 200, body: resp_body}} ->
          case Jason.decode(resp_body) do
            {:ok, %{"verification_status" => "SUCCESS"}} ->
              Jason.decode(payload)

            {:ok, _} ->
              {:error, :invalid_signature}

            {:error, reason} ->
              {:error, {:json_decode_error, reason}}
          end

        {:ok, %HTTPoison.Response{status_code: status, body: resp_body}} ->
          Logger.error("PayPal webhook verification failed (#{status}): #{resp_body}")
          {:error, {:paypal_error, status, resp_body}}

        {:error, %HTTPoison.Error{reason: reason}} ->
          Logger.error("PayPal HTTP error: #{inspect(reason)}")
          {:error, {:http_error, reason}}
      end
    end
  end

  @impl true
  def refund(capture_id, opts) do
    with {:ok, token} <- get_access_token() do
      url = "#{base_url()}/v2/payments/captures/#{capture_id}/refund"

      body =
        %{}
        |> maybe_put("amount", build_amount(opts))
        |> maybe_put("note_to_payer", Map.get(opts, :reason))
        |> Jason.encode!()

      case HTTPoison.post(url, body, auth_headers(token)) do
        {:ok, %HTTPoison.Response{status_code: status, body: resp_body}}
        when status in [200, 201] ->
          case Jason.decode(resp_body) do
            {:ok, refund_data} -> {:ok, refund_data}
            {:error, reason} -> {:error, {:json_decode_error, reason}}
          end

        {:ok, %HTTPoison.Response{status_code: status, body: resp_body}} ->
          Logger.error("PayPal refund failed (#{status}): #{resp_body}")
          {:error, {:paypal_error, status, resp_body}}

        {:error, %HTTPoison.Error{reason: reason}} ->
          Logger.error("PayPal HTTP error: #{inspect(reason)}")
          {:error, {:http_error, reason}}
      end
    end
  end

  @impl true
  def name, do: "paypal"

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp parse_amount(value) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> round(float * 100)
      :error -> 0
    end
  end

  defp parse_amount(value) when is_integer(value), do: value
  defp parse_amount(_), do: 0

  defp build_amount(%{amount: amount, currency: currency}) do
    %{"value" => to_string(amount), "currency_code" => String.upcase(to_string(currency))}
  end

  defp build_amount(_), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
