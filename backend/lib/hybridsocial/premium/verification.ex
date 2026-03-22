defmodule Hybridsocial.Premium.Verification do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_types ~w(manual domain paid)
  @valid_statuses ~w(pending approved rejected expired)

  schema "verifications" do
    field :type, :string
    field :status, :string, default: "pending"
    field :verified_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :identity, Hybridsocial.Accounts.Identity

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(verification, attrs) do
    verification
    |> cast(attrs, [:identity_id, :type, :status, :verified_at, :expires_at, :metadata])
    |> validate_required([:identity_id, :type])
    |> validate_inclusion(:type, @valid_types)
    |> validate_inclusion(:status, @valid_statuses)
    |> foreign_key_constraint(:identity_id)
  end

  def approve_changeset(verification) do
    verification
    |> change(status: "approved", verified_at: DateTime.utc_now())
  end

  def reject_changeset(verification) do
    verification
    |> change(status: "rejected")
  end
end
