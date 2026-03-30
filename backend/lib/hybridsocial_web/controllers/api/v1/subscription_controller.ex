defmodule HybridsocialWeb.Api.V1.SubscriptionController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Premium

  # GET /api/v1/subscriptions/plans
  def plans(conn, _params) do
    alias Hybridsocial.Premium.TierLimits

    tiers_enabled = TierLimits.enabled?()
    payment_configured = TierLimits.payment_configured?()
    all_tiers = TierLimits.all_tier_configs()

    tier_names = %{
      "free" => "Free",
      "verified_starter" => "Starter",
      "verified_creator" => "Creator",
      "verified_pro" => "Pro"
    }

    tier_prices = %{
      "free" => 0,
      "verified_starter" => Hybridsocial.Config.get("tier_verified_starter_price", 499),
      "verified_creator" => Hybridsocial.Config.get("tier_verified_creator_price", 999),
      "verified_pro" => Hybridsocial.Config.get("tier_verified_pro_price", 1999)
    }

    plans =
      TierLimits.tiers()
      |> Enum.map(fn tier ->
        limits = all_tiers[tier]
        %{
          id: tier,
          name: tier_names[tier] || tier,
          price: tier_prices[tier] || 0,
          currency: Hybridsocial.Config.get("subscription_currency", "USD"),
          limits: limits
        }
      end)

    conn
    |> put_status(:ok)
    |> json(%{
      plans: plans,
      tiers_enabled: tiers_enabled,
      payment_configured: payment_configured
    })
  end

  # POST /api/v1/subscriptions
  def create(conn, params) do
    identity = conn.assigns.current_identity

    attrs = %{
      plan: params["plan"] || "premium",
      payment_provider: params["payment_provider"],
      external_id: params["external_id"]
    }

    case Premium.create_subscription(identity.id, attrs) do
      {:ok, subscription} ->
        conn |> put_status(:created) |> json(serialize_subscription(subscription))

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  # GET /api/v1/subscriptions/current
  def current(conn, _params) do
    identity = conn.assigns.current_identity

    case Premium.get_subscription(identity.id) do
      nil ->
        conn |> put_status(:ok) |> json(%{plan: "free", status: "active"})

      subscription ->
        conn |> put_status(:ok) |> json(serialize_subscription(subscription))
    end
  end

  # DELETE /api/v1/subscriptions
  def cancel(conn, _params) do
    identity = conn.assigns.current_identity

    case Premium.cancel_subscription(identity.id) do
      {:ok, subscription} ->
        conn |> put_status(:ok) |> json(serialize_subscription(subscription))

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "subscription.not_found"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  # POST /api/v1/verification/apply
  def apply_verification(conn, params) do
    identity = conn.assigns.current_identity
    type = params["type"] || "manual"
    metadata = params["metadata"] || %{}

    case Premium.apply_for_verification(identity.id, type, metadata) do
      {:ok, verification} ->
        conn |> put_status(:created) |> json(serialize_verification(verification))

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  # GET /api/v1/verification/status
  def verification_status(conn, _params) do
    identity = conn.assigns.current_identity

    case Premium.get_verification(identity.id) do
      nil ->
        conn |> put_status(:ok) |> json(%{status: "none"})

      verification ->
        vouch_count = if verification.type == "peer_vouch", do: Premium.vouch_count(verification.id), else: 0
        conn |> put_status(:ok) |> json(Map.put(serialize_verification(verification), :vouch_count, vouch_count))
    end
  end

  # POST /api/v1/verification/vouch/:identity_id
  def vouch_for_user(conn, %{"identity_id" => target_identity_id}) do
    voucher = conn.assigns.current_identity

    case Premium.get_peer_verification(target_identity_id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "verification.no_pending_request"})

      verification ->
        case Premium.vouch_for(verification.id, voucher.id) do
          {:ok, _vouch} ->
            count = Premium.vouch_count(verification.id)
            json(conn, %{status: "vouched", vouch_count: count, required: 3})

          {:error, :already_vouched} ->
            conn |> put_status(:conflict) |> json(%{error: "verification.already_vouched"})

          {:error, :cannot_vouch_self} ->
            conn |> put_status(:unprocessable_entity) |> json(%{error: "verification.cannot_vouch_self"})

          {:error, _} ->
            conn |> put_status(:unprocessable_entity) |> json(%{error: "verification.vouch_failed"})
        end
    end
  end

  # GET /api/v1/verification/vouches/:identity_id
  def get_vouches(conn, %{"identity_id" => target_identity_id}) do
    case Premium.get_peer_verification(target_identity_id) do
      nil ->
        json(conn, %{vouches: [], count: 0, required: 3})

      verification ->
        vouches = Premium.get_vouches(verification.id)

        json(conn, %{
          count: length(vouches),
          required: 3,
          vouches: Enum.map(vouches, fn v ->
            %{
              id: v.id,
              voucher: %{
                id: v.voucher.id,
                handle: v.voucher.handle,
                display_name: v.voucher.display_name,
                avatar_url: v.voucher.avatar_url
              },
              created_at: v.inserted_at
            }
          end)
        })
    end
  end

  defp serialize_subscription(subscription) do
    %{
      id: subscription.id,
      plan: subscription.plan,
      status: subscription.status,
      payment_provider: subscription.payment_provider,
      started_at: subscription.started_at,
      expires_at: subscription.expires_at,
      cancelled_at: subscription.cancelled_at
    }
  end

  defp serialize_verification(verification) do
    %{
      id: verification.id,
      type: verification.type,
      status: verification.status,
      verified_at: verification.verified_at,
      expires_at: verification.expires_at
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
