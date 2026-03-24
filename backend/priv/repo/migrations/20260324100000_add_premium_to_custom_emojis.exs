defmodule Hybridsocial.Repo.Migrations.AddPremiumToCustomEmojis do
  use Ecto.Migration

  def change do
    alter table(:custom_emojis) do
      add :premium, :boolean, default: false, null: false
    end
  end
end
