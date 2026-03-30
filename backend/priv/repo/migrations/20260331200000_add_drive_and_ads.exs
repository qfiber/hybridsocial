defmodule Hybridsocial.Repo.Migrations.AddDriveAndAds do
  use Ecto.Migration

  def change do
    # Drive folders for media organization
    create table(:drive_folders, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :identity_id, references(:identities, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :parent_id, references(:drive_folders, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:drive_folders, [:identity_id])
    create index(:drive_folders, [:parent_id])

    # Add folder_id and content_hash to media
    alter table(:media) do
      add_if_not_exists :folder_id, references(:drive_folders, type: :binary_id, on_delete: :nilify_all)
      add_if_not_exists :content_hash, :string
    end

    create_if_not_exists index(:media, [:content_hash])
    create_if_not_exists index(:media, [:folder_id])

    # Ads system
    create table(:ads, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :description, :text
      add :image_url, :string
      add :link_url, :string, null: false
      add :placement, :string, default: "sidebar"  # sidebar, feed, banner
      add :priority, :integer, default: 0
      add :starts_at, :utc_datetime_usec
      add :expires_at, :utc_datetime_usec
      add :is_active, :boolean, default: true
      add :impressions, :integer, default: 0
      add :clicks, :integer, default: 0
      add :created_by_id, references(:identities, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:ads, [:placement, :is_active])
    create index(:ads, [:starts_at, :expires_at])
  end
end
