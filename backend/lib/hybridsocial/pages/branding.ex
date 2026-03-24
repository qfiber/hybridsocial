defmodule Hybridsocial.Pages.Branding do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:identity_id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "page_branding" do
    field :theme_color, :string
    field :cover_image_url, :string
    field :logo_url, :string
    field :layout_preference, :map, default: %{}

    belongs_to :organization, Hybridsocial.Accounts.Organization,
      foreign_key: :identity_id,
      references: :identity_id,
      define_field: false

    field :updated_at, :utc_datetime_usec
  end

  def changeset(branding, attrs) do
    # custom_css is intentionally excluded — CSS injection is a security risk
    branding
    |> cast(attrs, [:theme_color, :cover_image_url, :logo_url, :layout_preference])
    |> validate_length(:theme_color, max: 20)
    |> validate_length(:cover_image_url, max: 2048)
    |> validate_length(:logo_url, max: 2048)
    |> put_change(:updated_at, DateTime.utc_now() |> DateTime.truncate(:microsecond))
  end
end
