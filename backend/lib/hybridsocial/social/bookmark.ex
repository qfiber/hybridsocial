defmodule Hybridsocial.Social.Bookmark do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "bookmarks" do
    belongs_to :identity, Hybridsocial.Accounts.Identity
    belongs_to :post, Hybridsocial.Social.Post

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(bookmark, attrs) do
    bookmark
    |> cast(attrs, [:identity_id, :post_id])
    |> validate_required([:identity_id, :post_id])
    |> unique_constraint([:identity_id, :post_id])
    |> foreign_key_constraint(:identity_id)
    |> foreign_key_constraint(:post_id)
  end
end
