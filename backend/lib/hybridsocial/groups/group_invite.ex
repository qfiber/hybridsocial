defmodule Hybridsocial.Groups.GroupInvite do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "group_invites" do
    field :status, :string, default: "pending"

    belongs_to :group, Hybridsocial.Groups.Group
    belongs_to :inviter, Hybridsocial.Accounts.Identity, foreign_key: :invited_by
    belongs_to :invited, Hybridsocial.Accounts.Identity, foreign_key: :invited_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(invite, attrs) do
    invite
    |> cast(attrs, [:group_id, :invited_by, :invited_id, :status])
    |> validate_required([:group_id, :invited_by, :invited_id])
    |> validate_inclusion(:status, ~w(pending accepted declined))
    |> foreign_key_constraint(:group_id)
    |> foreign_key_constraint(:invited_by)
    |> foreign_key_constraint(:invited_id)
    |> unique_constraint([:group_id, :invited_id])
  end
end
