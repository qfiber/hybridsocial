defmodule Hybridsocial.Auth.Role do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "roles" do
    field :name, :string
    field :description, :string
    field :is_system, :boolean, default: false

    many_to_many :permissions, Hybridsocial.Auth.Permission,
      join_through: Hybridsocial.Auth.RolePermission

    has_many :identity_roles, Hybridsocial.Auth.IdentityRole

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(role, attrs) do
    role
    |> cast(attrs, [:name, :description, :is_system])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end

  def create_changeset(role, attrs) do
    role
    |> cast(attrs, [:name, :description])
    |> validate_required([:name])
    |> put_change(:is_system, false)
    |> unique_constraint(:name)
  end

  def update_changeset(role, attrs) do
    role
    |> cast(attrs, [:name, :description])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
