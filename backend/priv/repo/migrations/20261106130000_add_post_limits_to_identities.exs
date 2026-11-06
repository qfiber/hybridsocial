defmodule Hybridsocial.Repo.Migrations.AddPostLimitsToIdentities do
  use Ecto.Migration

  def change do
    # Its own column rather than `metadata`, which users can write to through
    # their own profile update. A limit they can edit isn't a limit.
    alter table(:identities) do
      add :post_limits, :map, null: false, default: %{}
    end
  end
end
