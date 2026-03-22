defmodule Hybridsocial.Repo.Migrations.CreateRbacTables do
  use Ecto.Migration

  def up do
    # --- Roles ---
    create table(:roles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :is_system, :boolean, default: false, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:roles, [:name])

    # --- Permissions ---
    create table(:permissions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :category, :string, null: false
    end

    create unique_index(:permissions, [:name])

    # --- Role-Permission mapping ---
    create table(:role_permissions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :role_id, references(:roles, type: :binary_id, on_delete: :delete_all), null: false

      add :permission_id, references(:permissions, type: :binary_id, on_delete: :delete_all),
        null: false
    end

    create unique_index(:role_permissions, [:role_id, :permission_id])

    # --- Identity-Role mapping ---
    create table(:identity_roles, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :identity_id, references(:identities, type: :binary_id, on_delete: :delete_all),
        null: false

      add :role_id, references(:roles, type: :binary_id, on_delete: :delete_all), null: false
      add :granted_by, references(:identities, type: :binary_id, on_delete: :nilify_all)
      add :granted_at, :utc_datetime_usec, null: false
      add :expires_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:identity_roles, [:identity_id, :role_id])
    create index(:identity_roles, [:identity_id])
    create index(:identity_roles, [:role_id])

    # --- Seed permissions ---
    flush()

    permissions = [
      # Users
      {"users.view", "View user accounts", "users"},
      {"users.suspend", "Suspend user accounts", "users"},
      {"users.delete", "Delete user accounts", "users"},
      {"users.warn", "Warn user accounts", "users"},
      # Reports
      {"reports.view", "View reports", "reports"},
      {"reports.manage", "Manage reports (resolve, dismiss)", "reports"},
      {"reports.assign", "Assign reports to moderators", "reports"},
      # Content
      {"content.delete", "Delete any content", "content"},
      {"content.filter_manage", "Manage content filters", "content"},
      # Federation
      {"federation.view", "View federation status", "federation"},
      {"federation.manage", "Manage federation policies", "federation"},
      {"federation.relay_manage", "Manage relays", "federation"},
      # Settings
      {"settings.view", "View instance settings", "settings"},
      {"settings.edit", "Edit instance settings", "settings"},
      # Backups
      {"backups.create", "Create backups", "backups"},
      {"backups.view", "View backups", "backups"},
      {"backups.restore", "Restore backups", "backups"},
      # Audit log
      {"audit_log.view", "View audit log", "audit_log"},
      # Announcements
      {"announcements.manage", "Manage announcements", "announcements"},
      # Custom emoji
      {"custom_emoji.manage", "Manage custom emojis", "custom_emoji"},
      # Email
      {"email.manage", "Manage email configuration", "email"},
      # Theme
      {"theme.manage", "Manage instance theme", "theme"},
      # Roles (meta)
      {"roles.view", "View roles", "roles"},
      {"roles.manage", "Manage roles and permissions", "roles"}
    ]

    perm_ids =
      for {name, description, category} <- permissions, into: %{} do
        id = Ecto.UUID.generate()

        execute("""
        INSERT INTO permissions (id, name, description, category)
        VALUES ('#{id}', '#{name}', '#{description}', '#{category}')
        """)

        {name, id}
      end

    # --- Seed system roles ---
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond) |> DateTime.to_iso8601()

    all_perm_names = Map.keys(perm_ids)

    admin_excluded = ["roles.manage"]
    admin_perms = all_perm_names -- admin_excluded

    moderator_perms = [
      "reports.view",
      "reports.manage",
      "reports.assign",
      "content.delete",
      "content.filter_manage",
      "users.view",
      "users.warn",
      "users.suspend",
      "audit_log.view",
      "announcements.manage"
    ]

    community_manager_perms = [
      "announcements.manage",
      "custom_emoji.manage",
      "content.filter_manage"
    ]

    roles = [
      {"owner", "Instance Owner", true, all_perm_names},
      {"admin", "Administrator", true, admin_perms},
      {"moderator", "Moderator", true, moderator_perms},
      {"community_manager", "Community Manager", true, community_manager_perms}
    ]

    for {name, description, is_system, role_perms} <- roles do
      role_id = Ecto.UUID.generate()

      execute("""
      INSERT INTO roles (id, name, description, is_system, inserted_at, updated_at)
      VALUES ('#{role_id}', '#{name}', '#{description}', #{is_system}, '#{now}', '#{now}')
      """)

      for perm_name <- role_perms do
        rp_id = Ecto.UUID.generate()
        perm_id = Map.fetch!(perm_ids, perm_name)

        execute("""
        INSERT INTO role_permissions (id, role_id, permission_id)
        VALUES ('#{rp_id}', '#{role_id}', '#{perm_id}')
        """)
      end
    end

    # --- Migrate existing is_admin users to owner role ---
    execute("""
    INSERT INTO identity_roles (id, identity_id, role_id, granted_by, granted_at, inserted_at, updated_at)
    SELECT
      gen_random_uuid(),
      i.id,
      r.id,
      i.id,
      now(),
      now(),
      now()
    FROM identities i
    CROSS JOIN roles r
    WHERE i.is_admin = true
      AND r.name = 'owner'
      AND NOT EXISTS (
        SELECT 1 FROM identity_roles ir WHERE ir.identity_id = i.id AND ir.role_id = r.id
      )
    """)
  end

  def down do
    drop table(:identity_roles)
    drop table(:role_permissions)
    drop table(:permissions)
    drop table(:roles)
  end
end
