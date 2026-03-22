defmodule Hybridsocial.Config.Setting do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:key, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime]

  schema "instance_settings" do
    field :value, :map
    field :type, :string, default: "string"
    field :category, :string, default: "general"
    field :description, :string
    field :updated_by, Ecto.UUID

    timestamps()
  end

  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:key, :value, :type, :category, :description, :updated_by])
    |> validate_required([:key, :value, :type, :category])
  end
end
