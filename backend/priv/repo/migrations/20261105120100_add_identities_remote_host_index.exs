defmodule Hybridsocial.Repo.Migrations.AddIdentitiesRemoteHostIndex do
  use Ecto.Migration

  # `identities` is live and large, so build without blocking writes.
  @disable_ddl_transaction true
  @disable_migration_lock true

  # Backs the instance-policy feed filters, which look up remote authors by the
  # host of `ap_actor_url`. The expression must match `Feeds.Visibility`.
  def up do
    execute("""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS identities_remote_host_index
    ON identities (lower(split_part(split_part(ap_actor_url, '/', 3), ':', 1)))
    WHERE is_local = false
    """)
  end

  def down do
    execute("DROP INDEX CONCURRENTLY IF EXISTS identities_remote_host_index")
  end
end
