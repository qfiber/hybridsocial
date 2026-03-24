defmodule Hybridsocial.Payments.Resolver do
  @moduledoc """
  Resolves the active payment gateway module at runtime.

  The gateway is determined by the `payment_gateway` setting stored in the
  database. Defaults to `Noop` when no gateway is configured, which is the
  expected state for self-hosted instances that don't charge users.
  """

  @doc "Return the payment gateway module for the current configuration."
  @spec impl() :: module()
  def impl do
    case Hybridsocial.Config.get("payment_gateway", "noop") do
      "stripe" -> Hybridsocial.Payments.Stripe
      "paypal" -> Hybridsocial.Payments.Paypal
      "crypto" -> Hybridsocial.Payments.Crypto
      _ -> Hybridsocial.Payments.Noop
    end
  end
end
