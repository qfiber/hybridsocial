defmodule Hybridsocial.Premium.Subscription do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_plans ~w(free premium emoji verified_starter verified_creator verified_pro)
  @valid_statuses ~w(active cancelled expired past_due)
  @valid_providers ~w(stripe paypal crypto)

  schema "subscriptions" do
    field :plan, :string, default: "free"
    field :status, :string, default: "active"
    field :payment_provider, :string
    field :external_id, :string
    field :started_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec
    field :cancelled_at, :utc_datetime_usec

    belongs_to :identity, Hybridsocial.Accounts.Identity

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [
      :identity_id,
      :plan,
      :status,
      :payment_provider,
      :external_id,
      :started_at,
      :expires_at
    ])
    |> validate_required([:identity_id, :plan])
    |> validate_inclusion(:plan, @valid_plans)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_provider()
    |> foreign_key_constraint(:identity_id)
  end

  def cancel_changeset(subscription) do
    subscription
    |> change(status: "cancelled", cancelled_at: DateTime.utc_now())
  end

  defp validate_provider(changeset) do
    case get_field(changeset, :payment_provider) do
      nil -> changeset
      _ -> validate_inclusion(changeset, :payment_provider, @valid_providers)
    end
  end
end
