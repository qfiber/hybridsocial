defmodule Hybridsocial.Repo.Migrations.AddPendingEmailChangeToUsers do
  use Ecto.Migration

  # A requested email change waits here until the new address is confirmed.
  # `pending_email` is encrypted at rest like `email`; the token column holds
  # only a SHA-256 of the emailed token.
  def change do
    alter table(:users) do
      add :pending_email, :string
      add :pending_email_token, :string
      add :pending_email_sent_at, :utc_datetime_usec
    end

    create index(:users, [:pending_email_token])
  end
end
