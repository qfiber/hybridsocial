defmodule Hybridsocial.Federation.Dedup do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:activity_hash, :string, autogenerate: false}

  schema "federation_dedup" do
    field :activity_id, :string
    # text column: activity ids are unbounded URLs (see the widening migration)
    field :processed_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec
  end

  def changeset(dedup, attrs) do
    dedup
    |> cast(attrs, [:activity_hash, :activity_id, :processed_at, :expires_at])
    |> validate_required([:activity_hash])
  end
end
