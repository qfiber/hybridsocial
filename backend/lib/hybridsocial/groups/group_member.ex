defmodule Hybridsocial.Groups.GroupMember do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "group_members" do
    field :role, Ecto.Enum, values: [:member, :moderator, :admin, :owner], default: :member
    field :status, Ecto.Enum, values: [:pending, :approved, :rejected, :banned], default: :approved

    belongs_to :group, Hybridsocial.Groups.Group
    belongs_to :identity, Hybridsocial.Accounts.Identity

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(member, attrs) do
    member
    |> cast(attrs, [:group_id, :identity_id, :role, :status])
    |> validate_required([:group_id, :identity_id])
    |> foreign_key_constraint(:group_id)
    |> foreign_key_constraint(:identity_id)
    |> unique_constraint([:group_id, :identity_id])
  end
end
