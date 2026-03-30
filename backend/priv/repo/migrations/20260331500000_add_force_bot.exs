defmodule Hybridsocial.Repo.Migrations.AddForceBot do
  use Ecto.Migration

  def change do
    alter table(:identities) do
      add :force_bot, :boolean, default: false
    end
  end
end
