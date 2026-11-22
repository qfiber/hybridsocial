defmodule Hybridsocial.Repo.Migrations.WidenFederationDedupActivityId do
  use Ecto.Migration

  # Activity ids are URLs with no length limit. Bridgy Fed's carry the full
  # percent-encoded article URL (600+ chars), so the varchar(255) insert
  # raised after the activity was processed, the inbox answered 500, and the
  # sender retried (and we reprocessed) every burst.
  def change do
    alter table(:federation_dedup) do
      modify :activity_id, :text, from: :string
    end
  end
end
