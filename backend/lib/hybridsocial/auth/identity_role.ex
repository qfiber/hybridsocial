defmodule Hybridsocial.Auth.IdentityRole do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "identity_roles" do
    belongs_to :identity, Hybridsocial.Accounts.Identity
    belongs_to :role, Hybridsocial.Auth.Role
    field :granted_by, :binary_id
    field :granted_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(identity_role, attrs) do
    identity_role
    |> cast(attrs, [:identity_id, :role_id, :granted_by, :granted_at, :expires_at])
    |> validate_required([:identity_id, :role_id, :granted_at])
    |> unique_constraint([:identity_id, :role_id])
    |> foreign_key_constraint(:identity_id)
    |> foreign_key_constraint(:role_id)
  end
end
