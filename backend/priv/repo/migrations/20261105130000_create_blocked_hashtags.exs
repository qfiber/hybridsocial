defmodule Hybridsocial.Repo.Migrations.CreateBlockedHashtags do
  use Ecto.Migration

  def change do
    create table(:blocked_hashtags, primary_key: false) do
      add :id, :binary_id, primary_key: true
      # The canonical lowercase tag, joined against `hashtags.name`. A name
      # rather than a foreign key, so a tag can be blocked before anyone uses it.
      add :name, :string, null: false
      add :action, :string, null: false, default: "no_trending"
      add :reason, :text
      add :created_by, references(:identities, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:blocked_hashtags, [:name])
  end
end
