defmodule Hybridsocial.Moderation.MediaHashBan do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_hash_types ~w(sha256 phash)

  # Uploads are only ever checked by their lowercase SHA-256 hex digest, so
  # anything else would save happily and then never match a file.
  @sha256_format ~r/^[0-9a-f]{64}$/

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
    |> update_change(:hash, &normalize_hash/1)
    |> validate_sha256()
    |> unique_constraint([:hash, :hash_type])
  end

  defp normalize_hash(hash) when is_binary(hash), do: hash |> String.trim() |> String.downcase()
  defp normalize_hash(hash), do: hash

  defp validate_sha256(changeset) do
    if get_field(changeset, :hash_type) == "sha256" do
      validate_format(changeset, :hash, @sha256_format,
        message: "must be a 64-character SHA-256 hash"
      )
    else
      changeset
    end
  end
end
