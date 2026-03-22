defmodule Hybridsocial.Pages.OrganizationRole do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_roles ~w(admin editor moderator)

  schema "organization_roles" do
    field :role, :string

    belongs_to :organization, Hybridsocial.Accounts.Organization,
      foreign_key: :organization_id,
      references: :identity_id

    belongs_to :identity, Hybridsocial.Accounts.Identity
    belongs_to :granted_by_identity, Hybridsocial.Accounts.Identity, foreign_key: :granted_by

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(role, attrs) do
    role
    |> cast(attrs, [:organization_id, :identity_id, :role, :granted_by])
    |> validate_required([:organization_id, :identity_id, :role])
    |> validate_inclusion(:role, @valid_roles)
    |> unique_constraint([:organization_id, :identity_id])
  end
end
