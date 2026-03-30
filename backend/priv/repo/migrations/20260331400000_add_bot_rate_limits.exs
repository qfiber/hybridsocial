defmodule Hybridsocial.Repo.Migrations.AddBotRateLimits do
  use Ecto.Migration

  def change do
    alter table(:bots) do
      add :posts_per_hour, :integer  # nil = use global default
    end
  end
end
