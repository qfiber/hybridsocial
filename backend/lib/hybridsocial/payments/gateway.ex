defmodule Hybridsocial.Payments.Gateway do
  @moduledoc """
  Behaviour definition for payment gateway adapters.

  All payment providers (Stripe, PayPal, crypto, etc.) must implement this
  behaviour. The active gateway is resolved at runtime via `Hybridsocial.Payments.Resolver`,
  allowing operators to switch providers through the admin panel without redeployment.
  """

  @doc "Create a checkout session for the given identity and plan."
  @callback create_checkout(identity_id :: String.t(), plan :: String.t(), opts :: map()) ::
              {:ok, %{session_id: String.t(), url: String.t()}} | {:error, term()}

  @doc "Verify a payment by its external (provider-side) identifier."
  @callback verify_payment(external_id :: String.t()) ::
              {:ok, %{status: String.t(), amount: integer(), currency: String.t()}}
              | {:error, term()}

  @doc "Cancel a subscription by its external identifier."
  @callback cancel_subscription(external_id :: String.t()) :: :ok | {:error, term()}

  @doc "Validate and parse an incoming webhook payload from the payment provider."
  @callback handle_webhook(payload :: binary(), headers :: map()) ::
              {:ok, map()} | {:error, term()}

  @doc "Issue a full or partial refund for a payment."
  @callback refund(external_id :: String.t(), opts :: map()) :: {:ok, map()} | {:error, term()}

  @doc "Return the human-readable name of this payment gateway."
  @callback name() :: String.t()
end
