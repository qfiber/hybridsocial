defmodule Hybridsocial.Pages.Branding do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:identity_id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "page_branding" do
    field :theme_color, :string
    field :cover_image_url, :string
    field :custom_css, :string
    field :logo_url, :string
    field :layout_preference, :map, default: %{}

    belongs_to :organization, Hybridsocial.Accounts.Organization,
      foreign_key: :identity_id,
      references: :identity_id,
      define_field: false

    field :updated_at, :utc_datetime_usec
  end

  def changeset(branding, attrs) do
    branding
    |> cast(attrs, [:theme_color, :cover_image_url, :custom_css, :logo_url, :layout_preference])
    |> sanitize_custom_css()
    |> put_change(:updated_at, DateTime.utc_now() |> DateTime.truncate(:microsecond))
  end

  defp sanitize_custom_css(changeset) do
    case get_change(changeset, :custom_css) do
      nil ->
        changeset

      css ->
        sanitized =
          css
          |> String.replace(~r/@import\b[^;]*;?/i, "")
          |> String.replace(~r/url\s*\([^)]*\)/i, "")
          |> String.replace(~r/expression\s*\([^)]*\)/i, "")
          |> String.replace(~r/javascript\s*:/i, "")

        put_change(changeset, :custom_css, sanitized)
    end
  end
end
