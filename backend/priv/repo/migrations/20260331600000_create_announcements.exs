defmodule Hybridsocial.Repo.Migrations.CreateAnnouncements do
  use Ecto.Migration

  def change do
    create table(:announcements, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :content, :text, null: false
      add :starts_at, :utc_datetime_usec
      add :ends_at, :utc_datetime_usec
      add :published, :boolean, default: true
      add :created_by, references(:identities, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end
  end
end
