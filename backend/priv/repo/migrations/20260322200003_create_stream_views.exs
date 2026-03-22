defmodule Hybridsocial.Repo.Migrations.CreateStreamViews do
  use Ecto.Migration

  def change do
    create table(:stream_views, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :post_id, references(:posts, type: :binary_id, on_delete: :delete_all), null: false
      add :identity_id, references(:identities, type: :binary_id, on_delete: :nilify_all)
      add :watch_duration, :float, null: false
      add :total_duration, :float, null: false
      add :completed, :boolean, default: false
      add :replayed, :boolean, default: false
      add :source, :string, default: "feed"
      timestamps(type: :utc_datetime_usec)
    end

    create index(:stream_views, [:post_id])
    create index(:stream_views, [:identity_id])
  end
end
