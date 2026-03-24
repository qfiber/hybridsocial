defmodule Hybridsocial.Repo.Migrations.AddSessionTrackingToOauthTokens do
  use Ecto.Migration

  def change do
    alter table(:oauth_tokens) do
      add :ip_address, :string
      add :user_agent, :text
      add :device_name, :string
      add :last_active_at, :utc_datetime_usec
    end
  end
end
