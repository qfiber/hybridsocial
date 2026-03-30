defmodule Hybridsocial.Markers.Marker do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "markers" do
    field :timeline, :string
    field :last_read_id, :string

    belongs_to :identity, Hybridsocial.Accounts.Identity

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(marker, attrs) do
    marker
    |> cast(attrs, [:identity_id, :timeline, :last_read_id])
    |> validate_required([:identity_id, :timeline, :last_read_id])
    |> validate_inclusion(:timeline, ["home", "notifications"])
    |> unique_constraint([:identity_id, :timeline])
  end
end
