defmodule Hybridsocial.Repo.Migrations.CreateSearchAndTrending do
  use Ecto.Migration

  def up do
    # Add tsvector column to posts for full-text search
    execute "ALTER TABLE posts ADD COLUMN search_vector tsvector"
    execute "CREATE INDEX posts_search_idx ON posts USING gin(search_vector)"

    # Create a trigger to auto-update search_vector on insert/update
    execute """
    CREATE OR REPLACE FUNCTION posts_search_update() RETURNS trigger AS $$
    BEGIN
      NEW.search_vector := to_tsvector('english', coalesce(NEW.content, ''));
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER posts_search_trigger
      BEFORE INSERT OR UPDATE OF content ON posts
      FOR EACH ROW EXECUTE FUNCTION posts_search_update();
    """

    # Add tsvector to identities for account search
    execute "ALTER TABLE identities ADD COLUMN search_vector tsvector"
    execute "CREATE INDEX identities_search_idx ON identities USING gin(search_vector)"

    execute """
    CREATE OR REPLACE FUNCTION identities_search_update() RETURNS trigger AS $$
    BEGIN
      NEW.search_vector := to_tsvector('english',
        coalesce(NEW.handle, '') || ' ' ||
        coalesce(NEW.display_name, '') || ' ' ||
        coalesce(NEW.bio, ''));
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER identities_search_trigger
      BEFORE INSERT OR UPDATE OF handle, display_name, bio ON identities
      FOR EACH ROW EXECUTE FUNCTION identities_search_update();
    """

    # Backfill existing rows
    execute "UPDATE posts SET search_vector = to_tsvector('english', coalesce(content, ''))"

    execute """
    UPDATE identities SET search_vector = to_tsvector('english',
      coalesce(handle, '') || ' ' ||
      coalesce(display_name, '') || ' ' ||
      coalesce(bio, ''))
    """

    # Trending data table (precomputed)
    create table(:trending_data, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :type, :string, null: false
      add :target_id, :string, null: false
      add :score, :float, default: 0
      add :metadata, :map, default: %{}
      add :computed_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:trending_data, [:type, :score], comment: "type + score desc for trending queries")
    create index(:trending_data, [:computed_at])
  end

  def down do
    execute "DROP TRIGGER IF EXISTS posts_search_trigger ON posts"
    execute "DROP FUNCTION IF EXISTS posts_search_update()"
    execute "DROP INDEX IF EXISTS posts_search_idx"
    execute "ALTER TABLE posts DROP COLUMN IF EXISTS search_vector"

    execute "DROP TRIGGER IF EXISTS identities_search_trigger ON identities"
    execute "DROP FUNCTION IF EXISTS identities_search_update()"
    execute "DROP INDEX IF EXISTS identities_search_idx"
    execute "ALTER TABLE identities DROP COLUMN IF EXISTS search_vector"

    drop table(:trending_data)
  end
end
