defmodule Hybridsocial.Social.List do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "lists" do
    field :name, :string

    belongs_to :identity, Hybridsocial.Accounts.Identity
    has_many :list_members, Hybridsocial.Social.ListMember

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(list, attrs) do
    list
    |> cast(attrs, [:name, :identity_id])
    |> validate_required([:name, :identity_id])
    |> validate_length(:name, min: 1, max: 255)
    |> foreign_key_constraint(:identity_id)
  end

  def update_changeset(list, attrs) do
    list
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
  end
end
