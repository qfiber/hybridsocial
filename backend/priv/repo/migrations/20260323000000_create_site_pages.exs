defmodule Hybridsocial.Repo.Migrations.CreateSitePages do
  use Ecto.Migration

  def change do
    create table(:site_pages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :string, null: false
      add :title, :string, null: false
      add :body_markdown, :text, null: false, default: ""
      add :body_html, :text, null: false, default: ""
      add :published, :boolean, null: false, default: false
      add :last_edited_by, references(:identities, type: :binary_id, on_delete: :nilify_all)
      add :deleted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:site_pages, [:slug], where: "deleted_at IS NULL")
  end
end
