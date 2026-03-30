defmodule Hybridsocial.Media.DriveFolder do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "drive_folders" do
    belongs_to :identity, Hybridsocial.Accounts.Identity
    belongs_to :parent, __MODULE__
    has_many :children, __MODULE__, foreign_key: :parent_id
    field :name, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(folder, attrs) do
    folder
    |> cast(attrs, [:identity_id, :name, :parent_id])
    |> validate_required([:identity_id, :name])
    |> validate_length(:name, min: 1, max: 100)
    |> foreign_key_constraint(:identity_id)
    |> foreign_key_constraint(:parent_id)
  end
end
