defmodule Hybridsocial.Search.TrendingData do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_types ~w(post hashtag link)

  schema "trending_data" do
    field :type, :string
    field :target_id, :string
    field :score, :float, default: 0.0
    field :metadata, :map, default: %{}
    field :computed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(trending_data, attrs) do
    trending_data
    |> cast(attrs, [:type, :target_id, :score, :metadata, :computed_at])
    |> validate_required([:type, :target_id, :computed_at])
    |> validate_inclusion(:type, @valid_types)
  end
end
