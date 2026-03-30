defmodule Hybridsocial.Social.FollowedTag do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "followed_tags" do
    belongs_to :identity, Hybridsocial.Accounts.Identity
    belongs_to :hashtag, Hybridsocial.Social.Hashtag

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(followed_tag, attrs) do
    followed_tag
    |> cast(attrs, [:identity_id, :hashtag_id])
    |> validate_required([:identity_id, :hashtag_id])
    |> unique_constraint([:identity_id, :hashtag_id])
    |> foreign_key_constraint(:identity_id)
    |> foreign_key_constraint(:hashtag_id)
  end
end
