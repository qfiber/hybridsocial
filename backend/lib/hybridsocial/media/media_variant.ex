defmodule Hybridsocial.Media.MediaVariant do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "media_variants" do
    field :resolution, :string
    field :storage_path, :string
    field :file_size, :integer
    field :content_type, :string

    belongs_to :media, Hybridsocial.Media.MediaFile

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(variant, attrs) do
    variant
    |> cast(attrs, [:media_id, :resolution, :storage_path, :file_size, :content_type])
    |> validate_required([:media_id, :storage_path])
    |> foreign_key_constraint(:media_id)
  end
end
