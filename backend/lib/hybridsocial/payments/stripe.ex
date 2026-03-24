defmodule Hybridsocial.Payments.Stripe do
  @moduledoc """
  Stripe payment gateway implementation.

  Communicates with the Stripe API using HTTPoison. Configuration values are
  read from `Hybridsocial.Config` at runtime with `System.get_env/1` fallbacks,
  so operators can set credentials either through the admin panel or environment
  variables.
  """

  @behaviour Hybridsocial.Payments.Gateway

  require Logger

  @base_url "https://api.stripe.com"

  # ---------------------------------------------------------------------------
  # Configuration helpers
  # ---------------------------------------------------------------------------

  defp secret_key do
    Hybridsocial.Config.get("stripe_secret_key") || System.get_env("STRIPE_SECRET_KEY")
  end

  defp webhook_secret do
    Hybridsocial.Config.get("stripe_webhook_secret") || System.get_env("STRIPE_WEBHOOK_SECRET")
  end

  defp auth_headers do
    [
      {"Authorization", "Bearer #{secret_key()}"},
      {"Content-Type", "application/x-www-form-urlencoded"}
    ]
  end

  # ---------------------------------------------------------------------------
  # Gateway callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def create_checkout(identity_id, plan, opts) do
    success_url = Map.get(opts, :success_url, "")
    cancel_url = Map.get(opts, :cancel_url, "")

    body =
      URI.encode_query(%{
        "mode" => "subscription",
        "client_reference_id" => identity_id,
        "success_url" => success_url,
        "cancel_url" => cancel_url,
        "line_items[0][price]" => plan,
        "line_items[0][quantity]" => "1"
      })

    case HTTPoison.post("#{@base_url}/v1/checkout/sessions", body, auth_headers()) do
      {:ok, %HTTPoison.Response{status_code: 200, body: resp_body}} ->
        case Jason.decode(resp_body) do
          {:ok, %{"id" => session_id, "url" => url}} ->
            {:ok, %{session_id: session_id, url: url}}

          {:ok, decoded} ->
            Logger.error("Stripe unexpected checkout response: #{inspect(decoded)}")
            {:error, :unexpected_response}

          {:error, reason} ->
            Logger.error("Stripe JSON decode error: #{inspect(reason)}")
            {:error, :json_decode_error}
        end

      {:ok, %HTTPoison.Response{status_code: status, body: resp_body}} ->
        Logger.error("Stripe create_checkout failed (#{status}): #{resp_body}")
        {:error, {:stripe_error, status, resp_body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Stripe HTTP error: #{inspect(reason)}")
        {:error, {:http_error, reason}}
    end
  end

  @impl true
  def verify_payment(payment_intent_id) do
    url = "#{@base_url}/v1/payment_intents/#{payment_intent_id}"

    case HTTPoison.get(url, auth_headers()) do
      {:ok, %HTTPoison.Response{status_code: 200, body: resp_body}} ->
        case Jason.decode(resp_body) do
          {:ok, %{"status" => status, "amount" => amount, "currency" => currency}} ->
            {:ok, %{status: status, amount: amount, currency: currency}}

          {:ok, decoded} ->
            Logger.error("Stripe unexpected verify response: #{inspect(decoded)}")
            {:error, :unexpected_response}

          {:error, reason} ->
            Logger.error("Stripe JSON decode error: #{inspect(reason)}")
            {:error, :json_decode_error}
        end

      {:ok, %HTTPoison.Response{status_code: status, body: resp_body}} ->
        Logger.error("Stripe verify_payment failed (#{status}): #{resp_body}")
        {:error, {:stripe_error, status, resp_body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Stripe HTTP error: #{inspect(reason)}")
        {:error, {:http_error, reason}}
    end
  end

  @impl true
  def cancel_subscription(subscription_id) do
    url = "#{@base_url}/v1/subscriptions/#{subscription_id}"

    case HTTPoison.delete(url, auth_headers()) do
      {:ok, %HTTPoison.Response{status_code: 200}} ->
        :ok

      {:ok, %HTTPoison.Response{status_code: status, body: resp_body}} ->
        Logger.error("Stripe cancel_subscription failed (#{status}): #{resp_body}")
        {:error, {:stripe_error, status, resp_body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Stripe HTTP error: #{inspect(reason)}")
        {:error, {:http_error, reason}}
    end
  end

  @impl true
  def handle_webhook(payload, headers) do
    signature = Map.get(headers, "stripe-signature", "")

    case verify_webhook_signature(payload, signature) do
      :ok ->
        case Jason.decode(payload) do
          {:ok, event} -> {:ok, event}
          {:error, reason} -> {:error, {:json_decode_error, reason}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def refund(payment_intent_id, opts) do
    body =
      %{"payment_intent" => payment_intent_id}
      |> maybe_put("amount", Map.get(opts, :amount))
      |> maybe_put("reason", Map.get(opts, :reason))
      |> URI.encode_query()

    case HTTPoison.post("#{@base_url}/v1/refunds", body, auth_headers()) do
      {:ok, %HTTPoison.Response{status_code: 200, body: resp_body}} ->
        case Jason.decode(resp_body) do
          {:ok, refund_data} -> {:ok, refund_data}
          {:error, reason} -> {:error, {:json_decode_error, reason}}
        end

      {:ok, %HTTPoison.Response{status_code: status, body: resp_body}} ->
        Logger.error("Stripe refund failed (#{status}): #{resp_body}")
        {:error, {:stripe_error, status, resp_body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Stripe HTTP error: #{inspect(reason)}")
        {:error, {:http_error, reason}}
    end
  end

  @impl true
  def name, do: "stripe"

  # ---------------------------------------------------------------------------
  # Webhook signature verification
  # ---------------------------------------------------------------------------

  defp verify_webhook_signature(payload, signature) do
    secret = webhook_secret()

    if is_nil(secret) || secret == "" do
      Logger.error("Stripe webhook secret not configured")
      {:error, :webhook_secret_not_configured}
    else
      parts =
        signature
        |> String.split(",")
        |> Enum.map(&String.split(&1, "=", parts: 2))
        |> Enum.reduce(%{}, fn
          [key, value], acc -> Map.put(acc, String.trim(key), String.trim(value))
          _, acc -> acc
        end)

      timestamp = Map.get(parts, "t", "")
      expected_sig = Map.get(parts, "v1", "")

      signed_payload = "#{timestamp}.#{payload}"

      computed =
        :crypto.mac(:hmac, :sha256, secret, signed_payload)
        |> Base.encode16(case: :lower)

      if Plug.Crypto.secure_compare(computed, expected_sig) do
        :ok
      else
        {:error, :invalid_signature}
      end
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
