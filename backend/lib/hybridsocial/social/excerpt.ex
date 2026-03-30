defmodule Hybridsocial.Social.Excerpt do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id


  schema "excerpts" do
    belongs_to :identity, Hybridsocial.Accounts.Identity
    field :name, :string
    field :keywords, {:array, :string}, default: []
    field :exclude_keywords, {:array, :string}, default: []
    field :sources, {:array, :string}, default: ["home", "local", "global"]
    field :with_media_only, :boolean, default: false
    field :notify, :boolean, default: false

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(excerpt, attrs) do
    excerpt
    |> cast(attrs, [:identity_id, :name, :keywords, :exclude_keywords, :sources, :with_media_only, :notify])
    |> validate_required([:identity_id, :name, :keywords])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:keywords, min: 1, max: 20)
    |> validate_length(:exclude_keywords, max: 20)
    |> foreign_key_constraint(:identity_id)
  end
end
