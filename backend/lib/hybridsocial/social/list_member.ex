defmodule Hybridsocial.Social.ListMember do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  @foreign_key_type :binary_id

  schema "list_members" do
    belongs_to :list, Hybridsocial.Social.List
    belongs_to :target_identity, Hybridsocial.Accounts.Identity

    field :added_at, :utc_datetime_usec
  end

  def changeset(list_member, attrs) do
    list_member
    |> cast(attrs, [:list_id, :target_identity_id])
    |> validate_required([:list_id, :target_identity_id])
    |> unique_constraint([:list_id, :target_identity_id])
    |> foreign_key_constraint(:list_id)
    |> foreign_key_constraint(:target_identity_id)
  end
end
