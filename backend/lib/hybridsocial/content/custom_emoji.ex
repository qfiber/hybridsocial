defmodule Hybridsocial.Content.CustomEmoji do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "custom_emojis" do
    field :shortcode, :string
    field :image_url, :string
    field :category, :string
    field :enabled, :boolean, default: true

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(emoji, attrs) do
    emoji
    |> cast(attrs, [:shortcode, :image_url, :category, :enabled])
    |> validate_required([:shortcode, :image_url])
    |> validate_format(:shortcode, ~r/\A[a-zA-Z0-9_]+\z/,
      message: "must only contain alphanumeric characters and underscores"
    )
    |> unique_constraint(:shortcode)
  end
end
