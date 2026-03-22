defmodule Hybridsocial.Repo.Migrations.CreatePosts do
  use Ecto.Migration

  def change do
    # Enum types
    execute(
      "CREATE TYPE post_visibility AS ENUM ('public', 'followers', 'group', 'direct', 'list')",
      "DROP TYPE post_visibility"
    )

    execute(
      "CREATE TYPE post_type AS ENUM ('text', 'media', 'video_stream', 'poll', 'article')",
      "DROP TYPE post_type"
    )

    execute(
      "CREATE TYPE reaction_type AS ENUM ('like', 'love', 'care', 'angry', 'sad', 'lol', 'wtf')",
      "DROP TYPE reaction_type"
    )

    # Posts
    create table(:posts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :identity_id, references(:identities, type: :binary_id, on_delete: :delete_all),
        null: false

      add :post_type, :post_type, default: "text"
      add :content, :text
      add :content_html, :text
      add :visibility, :post_visibility, default: "public"
      add :sensitive, :boolean, default: false
      add :spoiler_text, :string
      add :language, :string, size: 5
      add :group_id, :binary_id
      add :page_id, :binary_id
      add :list_id, :binary_id

      add :parent_id, references(:posts, type: :binary_id, on_delete: :nilify_all)
      add :root_id, references(:posts, type: :binary_id, on_delete: :nilify_all)
      add :quote_id, references(:posts, type: :binary_id, on_delete: :nilify_all)

      add :reply_count, :integer, default: 0
      add :boost_count, :integer, default: 0
      add :reaction_count, :integer, default: 0
      add :is_pinned, :boolean, default: false

      add :edited_at, :utc_datetime_usec
      add :edit_expires_at, :utc_datetime_usec
      add :scheduled_at, :utc_datetime_usec
      add :published_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
      add :deleted_at, :utc_datetime_usec
    end

    create index(:posts, [:identity_id])
    create index(:posts, [:parent_id])
    create index(:posts, [:root_id])
    create index(:posts, [:quote_id])
    create index(:posts, [:visibility])
    create index(:posts, [:deleted_at])
    create index(:posts, [:published_at])

    # Post revisions
    create table(:post_revisions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :post_id, references(:posts, type: :binary_id, on_delete: :delete_all), null: false

      add :content, :text
      add :content_html, :text
      add :edited_at, :utc_datetime_usec
      add :revision_number, :integer
    end

    create index(:post_revisions, [:post_id])

    # Reactions
    create table(:reactions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :post_id, references(:posts, type: :binary_id, on_delete: :delete_all), null: false

      add :identity_id, references(:identities, type: :binary_id, on_delete: :delete_all),
        null: false

      add :type, :reaction_type, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:reactions, [:post_id, :identity_id])

    # Boosts
    create table(:boosts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :post_id, references(:posts, type: :binary_id, on_delete: :delete_all), null: false

      add :identity_id, references(:identities, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime_usec)
      add :deleted_at, :utc_datetime_usec
    end

    create unique_index(:boosts, [:post_id, :identity_id])

    # Post recipients (for direct messages / lists)
    create table(:post_recipients, primary_key: false) do
      add :post_id, references(:posts, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :identity_id, references(:identities, type: :binary_id, on_delete: :delete_all),
        primary_key: true
    end

    # Hashtags
    create table(:hashtags, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :usage_count, :integer, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:hashtags, [:name])

    # Post-hashtag join table
    create table(:post_hashtags, primary_key: false) do
      add :post_id, references(:posts, type: :binary_id, on_delete: :delete_all), null: false

      add :hashtag_id, references(:hashtags, type: :binary_id, on_delete: :delete_all),
        null: false
    end

    create unique_index(:post_hashtags, [:post_id, :hashtag_id])
  end
end
