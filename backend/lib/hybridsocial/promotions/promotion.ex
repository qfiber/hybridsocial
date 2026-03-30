defmodule Hybridsocial.Promotions.Promotion do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_statuses ~w(pending active expired cancelled)

  schema "promotions" do
    field :status, :string, default: "pending"
    field :payment_provider, :string
    field :payment_id, :string
    field :amount_cents, :integer
    field :currency, :string, default: "USD"
    field :duration_days, :integer
    field :starts_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec
    field :deleted_at, :utc_datetime_usec

    belongs_to :identity, Hybridsocial.Accounts.Identity

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(promotion, attrs) do
    promotion
    |> cast(attrs, [
      :identity_id,
      :status,
      :payment_provider,
      :payment_id,
      :amount_cents,
      :currency,
      :duration_days,
      :starts_at,
      :expires_at
    ])
    |> validate_required([:identity_id, :duration_days])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_length(:payment_provider, max: 50)
    |> validate_length(:payment_id, max: 255)
    |> validate_length(:currency, max: 10)
    # duration_days: 0 = unlimited, max 90 days (3 months) for paid
    |> validate_number(:duration_days, greater_than_or_equal_to: 0, less_than_or_equal_to: 90)
  end

  def activate_changeset(promotion) do
    now = DateTime.utc_now()

    expires =
      if promotion.duration_days == 0 do
        nil  # unlimited
      else
        DateTime.add(now, promotion.duration_days * 86400, :second)
      end

    promotion
    |> change(status: "active", starts_at: now, expires_at: expires)
  end
end
