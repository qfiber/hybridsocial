defmodule Hybridsocial.Repo.Migrations.CreatePageBranding do
  use Ecto.Migration

  def change do
    create table(:page_branding, primary_key: false) do
      add :identity_id,
          references(:organizations,
            column: :identity_id,
            type: :binary_id,
            on_delete: :delete_all
          ),
          primary_key: true

      add :theme_color, :string
      add :cover_image_url, :string
      add :logo_url, :string
      add :layout_preference, :map, default: %{}

      add :updated_at, :utc_datetime_usec, null: false
    end
  end
end
