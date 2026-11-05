defmodule Hybridsocial.Repo.Migrations.NormalizeInstancePolicyDomains do
  use Ecto.Migration

  # Domains used to be saved exactly as typed, but matching is an exact compare
  # against the actor's lowercase host, so `Evil.Example` or `https://evil.example/`
  # were listed in the admin panel and enforced nothing. Repair those.
  #
  # Handles and URLs with a path are left alone: reducing `@bob@evil.example` to
  # its host would turn a one-account intent into blocking a whole instance. They
  # stay inert until an admin removes them. A row that would collide with an
  # existing one is also left for the admin.
  def up do
    execute("""
    UPDATE instance_policies p
    SET domain = n.norm
    FROM (
      SELECT DISTINCT ON (norm) domain, norm
      FROM (
        SELECT domain, updated_at,
               regexp_replace(
                 regexp_replace(lower(btrim(domain, E' \\t\\r\\n')), '^https?://', ''),
                 '/$', ''
               ) AS norm
        FROM instance_policies
      ) candidates
      ORDER BY norm, updated_at DESC
    ) n
    WHERE p.domain = n.domain
      AND n.norm <> p.domain
      AND n.norm <> ''
      AND n.norm !~ '[/@[:space:]]'
      AND NOT EXISTS (SELECT 1 FROM instance_policies o WHERE o.domain = n.norm)
    """)
  end

  def down, do: :ok
end
