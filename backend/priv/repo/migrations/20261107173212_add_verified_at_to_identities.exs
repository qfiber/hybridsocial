defmodule Hybridsocial.Repo.Migrations.AddVerifiedAtToIdentities do
  use Ecto.Migration

  # Admin verification marks the account itself, separately from the paid
  # `verification_tier` ladder (#168). Approving a request used to record only
  # the request's status, which nothing read, so approved users got no badge.
  def up do
    alter table(:identities) do
      add :verified_at, :utc_datetime_usec
      add :verified_by_id, references(:identities, type: :binary_id, on_delete: :nilify_all)
    end

    # Requests staff approved by hand. Peer-vouched approvals are left out:
    # three accounts vouching was never reviewed by anyone.
    execute("""
    UPDATE identities AS i
    SET verified_at = v.verified_at
    FROM (
      SELECT identity_id, max(coalesce(verified_at, updated_at)) AS verified_at
      FROM verifications
      WHERE status = 'approved' AND type = 'manual'
      GROUP BY identity_id
    ) AS v
    WHERE i.id = v.identity_id
    """)
  end

  def down do
    alter table(:identities) do
      remove :verified_by_id
      remove :verified_at
    end
  end
end
