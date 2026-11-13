defmodule Hybridsocial.Repo.Migrations.AddSettingsGroupPermissions do
  use Ecto.Migration

  @moduledoc """
  One permission per admin settings group (`Config.Registry.groups/0`).

  General keeps `settings.manage`, and Branding and Federation reuse
  `theme.manage` and `federation.manage`. The rest get a new permission,
  granted to every role that holds `settings.manage` today (owner and admin,
  plus any custom role an operator gave it), so nobody gains or loses access
  on deploy. Owners can then hand a group to a narrower role on the Roles page.
  """

  @new [
    {"settings.access", "Manage sign-up and access settings"},
    {"settings.posting", "Manage posting and account limits"},
    {"settings.media", "Manage media and storage settings"},
    {"settings.discovery", "Manage feed and discovery settings"},
    {"settings.moderation", "Manage moderation and safety settings"},
    {"settings.rate_limits", "Manage rate limits"},
    {"settings.monetization", "Manage monetization settings"},
    {"settings.integrations", "Manage third-party integrations"},
    {"settings.retention", "Manage data retention"}
  ]

  def up do
    for {name, description} <- @new do
      execute("""
      INSERT INTO permissions (id, name, description, category)
      VALUES ('#{Ecto.UUID.generate()}', '#{name}', '#{description}', 'settings')
      ON CONFLICT (name) DO NOTHING
      """)

      execute("""
      INSERT INTO role_permissions (id, role_id, permission_id)
      SELECT gen_random_uuid(), rp.role_id, p.id
        FROM role_permissions rp
        JOIN permissions src ON src.id = rp.permission_id AND src.name = 'settings.manage'
        CROSS JOIN permissions p
       WHERE p.name = '#{name}'
      ON CONFLICT (role_id, permission_id) DO NOTHING
      """)
    end
  end

  def down do
    names = Enum.map_join(@new, ", ", fn {name, _} -> "'#{name}'" end)

    execute("""
    DELETE FROM role_permissions
     WHERE permission_id IN (SELECT id FROM permissions WHERE name IN (#{names}))
    """)

    execute("DELETE FROM permissions WHERE name IN (#{names})")
  end
end
