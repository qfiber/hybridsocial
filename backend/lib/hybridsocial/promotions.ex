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
      currency: currency()
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
          currency: currency(),
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
        (is_nil(p.expires_at) or p.expires_at > ^now) and
        is_nil(p.deleted_at)
    )
    |> order_by([p], desc: p.inserted_at)
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
        (is_nil(p.expires_at) or p.expires_at > ^now) and
        is_nil(p.deleted_at)
    )
    |> Repo.exists?()
  end

  @doc "Get all currently promoted users for the sidebar."
  def get_promoted_users(opts \\ []) do
    now = DateTime.utc_now()
    limit = opts[:limit] || promotion_max_active()
    exclude_id = opts[:exclude_identity_id]

    query =
      Promotion
      |> where(
        [p],
        p.status == "active" and
          (is_nil(p.expires_at) or p.expires_at > ^now) and
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

  @doc "Check if a real payment gateway is configured (not noop)."
  def payment_configured? do
    Hybridsocial.Payments.Resolver.impl() != Hybridsocial.Payments.Noop
  end

  @doc "Get pricing — includes payment_configured flag."
  def currency do
    Hybridsocial.Config.get("subscription_currency", "USD")
  end

  def get_full_pricing do
    %{
      price_cents: promotion_price_cents(),
      duration_days: promotion_duration_days(),
      max_duration_days: 90,
      enabled: promotions_enabled?(),
      payment_configured: payment_configured?(),
      currency: currency()
    }
  end

  # ---- Admin functions ----

  @doc "Admin: manually promote a user (free, optionally unlimited)."
  def admin_promote(identity_id, opts \\ []) do
    duration_days = Keyword.get(opts, :duration_days, 0)  # 0 = unlimited

    %Promotion{}
    |> Promotion.changeset(%{
      identity_id: identity_id,
      amount_cents: 0,
      currency: currency(),
      duration_days: duration_days,
      payment_provider: "admin",
      status: "pending"
    })
    |> Repo.insert()
    |> case do
      {:ok, promo} -> activate_promotion(promo.id)
      error -> error
    end
  end

  @doc "Admin: cancel a promotion."
  def admin_cancel_promotion(promotion_id) do
    case get_promotion(promotion_id) do
      nil -> {:error, :not_found}
      promo ->
        promo
        |> Ecto.Changeset.change(status: "cancelled")
        |> Repo.update()
    end
  end

  @doc "Expire promotions that are past their expiry date."
  def expire_promotions do
    now = DateTime.utc_now()

    {count, _} =
      Promotion
      |> where([p], p.status == "active" and not is_nil(p.expires_at) and p.expires_at <= ^now)
      |> Repo.update_all(set: [status: "expired", updated_at: now])

    {:ok, count}
  end

  @doc "Create a user promotion with duration validation (max 90 days)."
  def create_promotion_with_duration(identity_id, duration_days) do
    cond do
      not promotions_enabled?() ->
        {:error, :promotions_disabled}

      not payment_configured?() ->
        {:error, :payment_not_configured}

      has_active_promotion?(identity_id) ->
        {:error, :already_promoted}

      duration_days < 1 or duration_days > 90 ->
        {:error, :invalid_duration}

      true ->
        price = promotion_price_cents() * div(duration_days, promotion_duration_days())
        price = max(price, promotion_price_cents())

        %Promotion{}
        |> Promotion.changeset(%{
          identity_id: identity_id,
          amount_cents: price,
          currency: currency(),
          duration_days: duration_days,
          status: "pending"
        })
        |> Repo.insert()
    end
  end
end
