defmodule Hybridsocial.Premium.Donation do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "donations" do
    field :amount, :decimal
    field :currency, :string
    field :platform, :string
    field :transaction_id, :string

    belongs_to :donor, Hybridsocial.Accounts.Identity, foreign_key: :donor_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(donation, attrs) do
    donation
    |> cast(attrs, [:donor_id, :amount, :currency, :platform, :transaction_id])
    |> validate_required([:amount, :currency])
    |> validate_length(:currency, max: 3)
    |> foreign_key_constraint(:donor_id)
  end
end
