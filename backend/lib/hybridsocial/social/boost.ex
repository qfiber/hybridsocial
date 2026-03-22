defmodule Hybridsocial.Social.Boost do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "boosts" do
    field :deleted_at, :utc_datetime_usec

    belongs_to :post, Hybridsocial.Social.Post
    belongs_to :identity, Hybridsocial.Accounts.Identity

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(boost, attrs) do
    boost
    |> cast(attrs, [:post_id, :identity_id])
    |> validate_required([:post_id, :identity_id])
    |> unique_constraint([:post_id, :identity_id])
    |> foreign_key_constraint(:post_id)
    |> foreign_key_constraint(:identity_id)
  end
end
