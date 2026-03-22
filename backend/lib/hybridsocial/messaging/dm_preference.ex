defmodule Hybridsocial.Messaging.DmPreference do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:identity_id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  @valid_allow_from ~w(everyone followers mutual_followers nobody)

  schema "dm_preferences" do
    field :allow_dms_from, :string, default: "everyone"
    field :allow_group_dms, :boolean, default: false
  end

  def changeset(preference, attrs) do
    preference
    |> cast(attrs, [:identity_id, :allow_dms_from, :allow_group_dms])
    |> validate_inclusion(:allow_dms_from, @valid_allow_from)
    |> foreign_key_constraint(:identity_id)
  end
end
