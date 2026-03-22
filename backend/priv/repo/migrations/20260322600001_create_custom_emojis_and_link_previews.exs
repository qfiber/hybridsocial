defmodule Hybridsocial.Repo.Migrations.CreateCustomEmojisAndLinkPreviews do
  use Ecto.Migration

  def change do
    create table(:custom_emojis, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :shortcode, :string, null: false
      add :image_url, :string, null: false
      add :category, :string
      add :enabled, :boolean, default: true

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:custom_emojis, [:shortcode])

    create table(:link_previews, primary_key: false) do
      add :url_hash, :string, primary_key: true
      add :url, :text, null: false
      add :title, :string
      add :description, :text
      add :image_url, :string
      add :site_name, :string
      add :fetched_at, :utc_datetime_usec, null: false
      add :ttl, :integer, default: 86400

      timestamps(type: :utc_datetime_usec)
    end
  end
end
