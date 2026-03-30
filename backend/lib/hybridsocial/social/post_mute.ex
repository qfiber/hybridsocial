defmodule Hybridsocial.Social.PostMute do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "post_mutes" do
    belongs_to :post, Hybridsocial.Social.Post
    belongs_to :identity, Hybridsocial.Accounts.Identity

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(post_mute, attrs) do
    post_mute
    |> cast(attrs, [:post_id, :identity_id])
    |> validate_required([:post_id, :identity_id])
    |> foreign_key_constraint(:post_id)
    |> foreign_key_constraint(:identity_id)
    |> unique_constraint([:post_id, :identity_id])
  end
end
