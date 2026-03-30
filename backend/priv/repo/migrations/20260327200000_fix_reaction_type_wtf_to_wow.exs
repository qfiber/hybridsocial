defmodule Hybridsocial.Repo.Migrations.FixReactionTypeWtfToWow do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute "ALTER TYPE reaction_type ADD VALUE IF NOT EXISTS 'wow'"
    execute "UPDATE reactions SET type = 'wow' WHERE type = 'wtf'"
  end

  def down do
    execute "UPDATE reactions SET type = 'wtf' WHERE type = 'wow'"
  end
end
