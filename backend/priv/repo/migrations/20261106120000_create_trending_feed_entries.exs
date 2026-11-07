defmodule Hybridsocial.Repo.Migrations.CreateTrendingFeedEntries do
  use Ecto.Migration

  def change do
    create table(:trending_feed_entries, primary_key: false) do
      add :post_id, references(:posts, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      # Position in the blended feed. Local and remote posts are ranked apart
      # and interleaved, so this is the sort key rather than `score`.
      add :slot, :float, null: false
      add :score, :float, null: false
      add :is_local, :boolean, null: false
      # Why the post is in the feed, when its engagement alone doesn't explain it.
      add :reason_type, :string
      add :reason_tag, :string
      # Rows retired by a refresh stay for a while so a reader's cursor still
      # resolves mid-scroll.
      add :active, :boolean, null: false, default: true
      add :computed_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:trending_feed_entries, [:slot, :post_id], where: "active")
    create index(:trending_feed_entries, [:computed_at], where: "NOT active")
  end
end
