defmodule Hybridsocial.Repo.Migrations.AddModerationFieldsToIdentities do
  use Ecto.Migration

  def change do
    alter table(:identities) do
      add :is_silenced, :boolean, default: false, null: false
      add :silenced_until, :utc_datetime_usec
      add :silence_reason, :string
      add :is_shadow_banned, :boolean, default: false, null: false
      add :force_sensitive, :boolean, default: false, null: false
    end

    create index(:identities, [:is_silenced], where: "is_silenced = true")
    create index(:identities, [:is_shadow_banned], where: "is_shadow_banned = true")
  end
end
