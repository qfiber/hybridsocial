defmodule Hybridsocial.Social.Reaction do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_types ~w(like love care angry sad lol wtf)

  schema "reactions" do
    field :type, :string

    belongs_to :post, Hybridsocial.Social.Post
    belongs_to :identity, Hybridsocial.Accounts.Identity

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(reaction, attrs) do
    reaction
    |> cast(attrs, [:post_id, :identity_id, :type])
    |> validate_required([:post_id, :identity_id, :type])
    |> validate_inclusion(:type, @valid_types)
    |> unique_constraint([:post_id, :identity_id])
    |> foreign_key_constraint(:post_id)
    |> foreign_key_constraint(:identity_id)
  end

  def valid_types, do: @valid_types
end
