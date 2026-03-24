defmodule Hybridsocial.Moderation.MediaHashBan do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_hash_types ~w(sha256 phash)

  schema "media_hash_bans" do
    field :hash, :string
    field :hash_type, :string, default: "sha256"
    field :description, :string

    belongs_to :created_by_identity, Hybridsocial.Accounts.Identity, foreign_key: :created_by

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(media_hash_ban, attrs) do
    media_hash_ban
    |> cast(attrs, [:hash, :hash_type, :description, :created_by])
    |> validate_required([:hash, :hash_type, :created_by])
    |> validate_inclusion(:hash_type, @valid_hash_types)
    |> unique_constraint([:hash, :hash_type])
  end
end
