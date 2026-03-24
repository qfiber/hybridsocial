defmodule HybridsocialWeb.Api.V1.SubscriptionController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Premium

  # GET /api/v1/subscriptions/plans
  def plans(conn, _params) do
    plans = [
      %{
        id: "free",
        name: "Free",
        price: 0,
        features: ["basic_posting", "follows", "messaging"]
      },
      %{
        id: "premium",
        name: "Premium",
        price: 999,
        currency: "USD",
        features: [
          "markdown",
          "extended_post_length",
          "extra_reactions",
          "scheduled_posts",
          "post_analytics",
          "hd_video"
        ]
      }
    ]

    conn |> put_status(:ok) |> json(%{plans: plans})
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

  # POST /api/v1/verification/domain
  def verify_domain(conn, %{"domain" => domain}) do
    identity = conn.assigns.current_identity

    case Premium.verify_domain(identity.id, domain) do
      {:ok, verification} ->
        conn |> put_status(:ok) |> json(serialize_verification(verification))

      {:error, :domain_not_verified} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          error: "verification.domain_not_verified",
          instructions: %{
            dns: "Add a TXT record: hybridsocial-verify=#{identity.handle}",
            rel_me: "Add <a rel=\"me\" href=\"#{HybridsocialWeb.Endpoint.url()}/@#{identity.handle}\"> to your website"
          }
        })

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "account.not_found"})
    end
  end

  def verify_domain(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "verification.domain_required"})
  end

  # GET /api/v1/verification/status
  def verification_status(conn, _params) do
    identity = conn.assigns.current_identity

    case Premium.get_verification(identity.id) do
      nil ->
        conn |> put_status(:ok) |> json(%{status: "none"})

      verification ->
        conn |> put_status(:ok) |> json(serialize_verification(verification))
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
