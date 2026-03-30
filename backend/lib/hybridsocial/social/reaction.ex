defmodule Hybridsocial.Social.Reaction do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_types ~w(like love care angry sad lol wow)

  schema "reactions" do
    field :type, :string

    belongs_to :post, Hybridsocial.Social.Post
    belongs_to :identity, Hybridsocial.Accounts.Identity

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(reaction, attrs, opts \\ []) do
    reaction
    |> cast(attrs, [:post_id, :identity_id, :type])
    |> validate_required([:post_id, :identity_id, :type])
    |> validate_type(opts)
    |> unique_constraint([:post_id, :identity_id])
    |> foreign_key_constraint(:post_id)
    |> foreign_key_constraint(:identity_id)
  end

  defp validate_type(changeset, opts) do
    custom_emoji_allowed = Keyword.get(opts, :custom_emoji_allowed, false)

    if custom_emoji_allowed do
      # Premium users: allow standard types or custom emoji shortcodes (e.g. :fire:)
      changeset
      |> validate_format(:type, ~r/\A([a-z]+|:[a-zA-Z0-9_]+:)\z/,
        message: "must be a valid reaction type or custom emoji shortcode"
      )
    else
      validate_inclusion(changeset, :type, @valid_types)
    end
  end

  def valid_types, do: @valid_types
end
