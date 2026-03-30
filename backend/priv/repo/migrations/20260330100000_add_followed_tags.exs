defmodule Hybridsocial.Repo.Migrations.AddFollowedTags do
  use Ecto.Migration

  def change do
    create table(:followed_tags, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :identity_id, references(:identities, type: :binary_id, on_delete: :delete_all), null: false
      add :hashtag_id, references(:hashtags, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:followed_tags, [:identity_id, :hashtag_id])
    create index(:followed_tags, [:identity_id])
    create index(:followed_tags, [:hashtag_id])
  end
end
