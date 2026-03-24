defmodule Hybridsocial.Payments.Noop do
  @moduledoc """
  No-op payment gateway for instances that do not use paid subscriptions.

  This is the default gateway. Every mutation returns a descriptive error so
  callers can surface an appropriate message to the user. Read-only operations
  return neutral defaults.
  """

  @behaviour Hybridsocial.Payments.Gateway

  require Logger

  @impl true
  def create_checkout(_identity_id, _plan, _opts) do
    Logger.debug("Noop payment gateway: create_checkout called")
    {:error, :payments_not_configured}
  end

  @impl true
  def verify_payment(_external_id) do
    Logger.debug("Noop payment gateway: verify_payment called")
    {:error, :payments_not_configured}
  end

  @impl true
  def cancel_subscription(_external_id) do
    Logger.debug("Noop payment gateway: cancel_subscription called")
    {:error, :payments_not_configured}
  end

  @impl true
  def handle_webhook(_payload, _headers) do
    Logger.debug("Noop payment gateway: handle_webhook called")
    {:error, :payments_not_configured}
  end

  @impl true
  def refund(_external_id, _opts) do
    Logger.debug("Noop payment gateway: refund called")
    {:error, :payments_not_configured}
  end

  @impl true
  def name, do: "noop"
end
