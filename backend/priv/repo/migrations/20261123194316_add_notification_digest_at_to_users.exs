defmodule Hybridsocial.Repo.Migrations.AddNotificationDigestAtToUsers do
  use Ecto.Migration

  # End of the last notification-digest window for this user (#318). The
  # digest frequency itself lives in `users.preferences`, which the client
  # writes; this column is server-only so a client can't rewind it and
  # re-trigger digests.
  def change do
    alter table(:users) do
      add :notification_digest_at, :utc_datetime_usec
    end
  end
end
