defmodule Hybridsocial.Premium.Funding do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_platforms ~w(stripe paypal bitcoin ethereum custom)

  schema "instance_funding" do
    field :platform, :string
    field :config, :map, default: %{}
    field :enabled, :boolean, default: false
    field :display_text, :string
    field :goal_amount, :decimal
    field :current_amount, :decimal

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(funding, attrs) do
    funding
    |> cast(attrs, [:platform, :config, :enabled, :display_text, :goal_amount, :current_amount])
    |> validate_required([:platform])
    |> validate_inclusion(:platform, @valid_platforms)
  end
end
