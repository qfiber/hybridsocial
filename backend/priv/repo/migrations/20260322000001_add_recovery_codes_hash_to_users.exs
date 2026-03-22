defmodule Hybridsocial.Repo.Migrations.AddRecoveryCodesHashToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :recovery_codes_hash, :string
    end
  end
end
