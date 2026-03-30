defmodule HybridsocialWeb.Api.V1.PromotionController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Promotions

  @doc "GET /api/v1/promotions/pricing — public pricing info"
  def pricing(conn, _params) do
    pricing = Promotions.get_full_pricing()
    json(conn, %{data: pricing})
  end

  @doc "GET /api/v1/promotions/promoted — get promoted users for sidebar"
  def promoted(conn, _params) do
    exclude_id =
      case conn.assigns[:current_identity] do
        %{id: id} -> id
        _ -> nil
      end

    promotions = Promotions.get_promoted_users(exclude_identity_id: exclude_id)

    users =
      Enum.map(promotions, fn promo ->
        identity = promo.identity

        %{
          id: identity.id,
          handle: identity.handle,
          display_name: identity.display_name || identity.handle,
          avatar_url: identity.avatar_url,
          promoted: true
        }
      end)

    json(conn, %{data: users})
  end

  @doc "POST /api/v1/promotions — purchase a promotion"
  def create(conn, _params) do
    identity_id = conn.assigns.current_identity.id

    case Promotions.create_promotion(identity_id) do
      {:ok, promotion} ->
        # In production, this is where you'd create a payment intent
        # with Stripe/PayPal and return the client secret.
        # For now, we auto-activate to simulate payment.
        {:ok, activated} = Promotions.activate_promotion(promotion.id)

        conn
        |> put_status(:created)
        |> json(%{
          data: serialize(activated),
          # Payment integration placeholder:
          # payment_client_secret: "pi_xxx_secret_xxx"
          message: "Promotion activated successfully"
        })

      {:error, :promotions_disabled} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "promotions.disabled"})

      {:error, :already_promoted} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "promotions.already_active"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  @doc "GET /api/v1/promotions/me — get current user's promotion status"
  def status(conn, _params) do
    identity_id = conn.assigns.current_identity.id

    case Promotions.get_active_promotion(identity_id) do
      nil ->
        json(conn, %{data: nil, pricing: Promotions.get_pricing()})

      promotion ->
        json(conn, %{data: serialize(promotion)})
    end
  end

  @doc "GET /api/v1/promotions/history — get user's promotion history"
  def history(conn, _params) do
    identity_id = conn.assigns.current_identity.id
    promotions = Promotions.list_promotions(identity_id)
    json(conn, %{data: Enum.map(promotions, &serialize/1)})
  end

  defp serialize(promotion) do
    %{
      id: promotion.id,
      status: promotion.status,
      amount_cents: promotion.amount_cents,
      currency: promotion.currency,
      duration_days: promotion.duration_days,
      starts_at: promotion.starts_at,
      expires_at: promotion.expires_at,
      created_at: promotion.inserted_at
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
