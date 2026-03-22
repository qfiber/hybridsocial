defmodule Hybridsocial.Repo.Migrations.CreateBookmarksPolls do
  use Ecto.Migration

  def change do
    # Bookmarks
    create table(:bookmarks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :identity_id, references(:identities, type: :binary_id, on_delete: :delete_all),
        null: false

      add :post_id, references(:posts, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:bookmarks, [:identity_id, :post_id])
    create index(:bookmarks, [:identity_id])

    # Polls
    create table(:polls, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :post_id, references(:posts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :multiple_choice, :boolean, default: false
      add :expires_at, :utc_datetime_usec
      add :voters_count, :integer, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    create index(:polls, [:post_id])

    # Poll options
    create table(:poll_options, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :poll_id, references(:polls, type: :binary_id, on_delete: :delete_all),
        null: false

      add :text, :string, null: false
      add :position, :integer, null: false
      add :votes_count, :integer, default: 0
    end

    create index(:poll_options, [:poll_id])

    # Poll votes
    create table(:poll_votes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :poll_id, references(:polls, type: :binary_id, on_delete: :delete_all),
        null: false

      add :option_id, references(:poll_options, type: :binary_id, on_delete: :delete_all),
        null: false

      add :identity_id, references(:identities, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:poll_votes, [:poll_id, :identity_id, :option_id])
    create index(:poll_votes, [:poll_id])
    create index(:poll_votes, [:identity_id])
  end
end
