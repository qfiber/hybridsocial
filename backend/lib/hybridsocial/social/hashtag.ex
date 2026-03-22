defmodule Hybridsocial.Social.Hashtag do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "hashtags" do
    field :name, :string
    field :usage_count, :integer, default: 0

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(hashtag, attrs) do
    hashtag
    |> cast(attrs, [:name, :usage_count])
    |> validate_required([:name])
    |> update_change(:name, &String.downcase/1)
    |> unique_constraint(:name)
  end
end
