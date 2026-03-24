defmodule Hybridsocial.Promotions do
  @moduledoc """
  Context for managing user promotions ("Who to follow" placement).
  Users pay to have their profile promoted in the suggestions sidebar.
  """

  import Ecto.Query
  alias Hybridsocial.Repo
  alias Hybridsocial.Promotions.Promotion
  alias Hybridsocial.Config.Store

  # ---- Config helpers (read from admin settings) ----

  def promotion_price_cents do
    Store.get("promotion_price_cents", 150)
  end

  def promotion_duration_days do
    Store.get("promotion_duration_days", 30)
  end

  def promotions_enabled? do
    Store.get("promotions_enabled", true)
  end

  def promotion_max_active do
    Store.get("promotion_max_active", 10)
  end

  # ---- Public API ----

  @doc "Get the current promotion config for display to users."
  def get_pricing do
    %{
      price_cents: promotion_price_cents(),
      duration_days: promotion_duration_days(),
      enabled: promotions_enabled?(),
      currency: "USD"
    }
  end

  @doc "Create a new promotion purchase (pending payment)."
  def create_promotion(identity_id) do
    unless promotions_enabled?() do
      {:error, :promotions_disabled}
    else
      # Check if user already has an active promotion
      if has_active_promotion?(identity_id) do
        {:error, :already_promoted}
      else
        %Promotion{}
        |> Promotion.changeset(%{
          identity_id: identity_id,
          amount_cents: promotion_price_cents(),
          currency: "USD",
          duration_days: promotion_duration_days(),
          status: "pending"
        })
        |> Repo.insert()
      end
    end
  end

  @doc """
  Activate a promotion after payment confirmation.
  In production, this would be called by the payment webhook.
  For now, it can be called directly to simulate payment.
  """
  def activate_promotion(promotion_id) do
    case get_promotion(promotion_id) do
      nil ->
        {:error, :not_found}

      %Promotion{status: "pending"} = promotion ->
        promotion
        |> Promotion.activate_changeset()
        |> Repo.update()

      %Promotion{status: "active"} ->
        {:error, :already_active}

      _ ->
        {:error, :invalid_status}
    end
  end

  @doc "Get a promotion by ID."
  def get_promotion(id) do
    Promotion
    |> where([p], p.id == ^id and is_nil(p.deleted_at))
    |> Repo.one()
  end

  @doc "Get the active promotion for an identity."
  def get_active_promotion(identity_id) do
    now = DateTime.utc_now()

    Promotion
    |> where(
      [p],
      p.identity_id == ^identity_id and
        p.status == "active" and
        p.expires_at > ^now and
        is_nil(p.deleted_at)
    )
    |> order_by([p], desc: p.expires_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc "Check if an identity has an active promotion."
  def has_active_promotion?(identity_id) do
    now = DateTime.utc_now()

    Promotion
    |> where(
      [p],
      p.identity_id == ^identity_id and
        p.status == "active" and
        p.expires_at > ^now and
        is_nil(p.deleted_at)
    )
    |> Repo.exists?()
  end

  @doc "Get all currently promoted users (for the 'Who to follow' sidebar)."
  def get_promoted_users(opts \\ []) do
    now = DateTime.utc_now()
    limit = opts[:limit] || promotion_max_active()
    exclude_id = opts[:exclude_identity_id]

    query =
      Promotion
      |> where(
        [p],
        p.status == "active" and
          p.expires_at > ^now and
          is_nil(p.deleted_at)
      )
      |> order_by(fragment("RANDOM()"))
      |> limit(^limit)

    query =
      if exclude_id do
        where(query, [p], p.identity_id != ^exclude_id)
      else
        query
      end

    query
    |> Repo.all()
    |> Repo.preload(identity: [:user])
  end

  @doc "Get promotion history for an identity."
  def list_promotions(identity_id) do
    Promotion
    |> where([p], p.identity_id == ^identity_id and is_nil(p.deleted_at))
    |> order_by([p], desc: p.inserted_at)
    |> Repo.all()
  end

  @doc "Admin: list all promotions."
  def list_all_promotions(opts \\ []) do
    limit = opts[:limit] || 50
    offset = opts[:offset] || 0
    status = opts[:status]

    query =
      Promotion
      |> where([p], is_nil(p.deleted_at))
      |> order_by([p], desc: p.inserted_at)
      |> limit(^limit)
      |> offset(^offset)

    query =
      if status do
        where(query, [p], p.status == ^status)
      else
        query
      end

    query
    |> Repo.all()
    |> Repo.preload(:identity)
  end

  @doc "Expire promotions that are past their expiry date."
  def expire_promotions do
    now = DateTime.utc_now()

    {count, _} =
      Promotion
      |> where([p], p.status == "active" and p.expires_at <= ^now)
      |> Repo.update_all(set: [status: "expired", updated_at: now])

    {:ok, count}
  end
end
