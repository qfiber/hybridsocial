defmodule Hybridsocial.Premium.VerificationVouch do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "verification_vouches" do
    belongs_to :verification, Hybridsocial.Premium.Verification
    belongs_to :voucher, Hybridsocial.Accounts.Identity, foreign_key: :voucher_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(vouch, attrs) do
    vouch
    |> cast(attrs, [:verification_id, :voucher_id])
    |> validate_required([:verification_id, :voucher_id])
    |> unique_constraint([:verification_id, :voucher_id])
    |> foreign_key_constraint(:verification_id)
    |> foreign_key_constraint(:voucher_id)
  end
end
