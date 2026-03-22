defmodule Hybridsocial.Auth.RBAC do
  @moduledoc """
  Role-Based Access Control context.
  Manages roles, permissions, and identity-role assignments.
  """

  import Ecto.Query
  alias Hybridsocial.Repo
  alias Hybridsocial.Auth.{Role, Permission, RolePermission, IdentityRole}

  # ── Permission Checks ──────────────────────────────────────────────

  @doc "Check if an identity has a specific permission via any of its active roles."
  def has_permission?(identity_id, permission_name) do
    now = DateTime.utc_now()

    from(ir in IdentityRole,
      join: r in Role,
      on: ir.role_id == r.id,
      join: rp in RolePermission,
      on: rp.role_id == r.id,
      join: p in Permission,
      on: rp.permission_id == p.id,
      where: ir.identity_id == ^identity_id,
      where: p.name == ^permission_name,
      where: is_nil(ir.expires_at) or ir.expires_at > ^now
    )
    |> Repo.exists?()
  end

  @doc "Check if an identity has any of the listed permissions."
  def has_any_permission?(identity_id, permission_names) when is_list(permission_names) do
    now = DateTime.utc_now()

    from(ir in IdentityRole,
      join: r in Role,
      on: ir.role_id == r.id,
      join: rp in RolePermission,
      on: rp.role_id == r.id,
      join: p in Permission,
      on: rp.permission_id == p.id,
      where: ir.identity_id == ^identity_id,
      where: p.name in ^permission_names,
      where: is_nil(ir.expires_at) or ir.expires_at > ^now
    )
    |> Repo.exists?()
  end

  @doc "Check if an identity has all of the listed permissions."
  def has_all_permissions?(identity_id, permission_names) when is_list(permission_names) do
    now = DateTime.utc_now()
    required_count = length(permission_names)

    count =
      from(ir in IdentityRole,
        join: r in Role,
        on: ir.role_id == r.id,
        join: rp in RolePermission,
        on: rp.role_id == r.id,
        join: p in Permission,
        on: rp.permission_id == p.id,
        where: ir.identity_id == ^identity_id,
        where: p.name in ^permission_names,
        where: is_nil(ir.expires_at) or ir.expires_at > ^now,
        select: count(p.name, :distinct)
      )
      |> Repo.one()

    count == required_count
  end

  @doc "Check if an identity has any active role (i.e. is staff)."
  def is_staff?(identity_id) do
    now = DateTime.utc_now()

    from(ir in IdentityRole,
      where: ir.identity_id == ^identity_id,
      where: is_nil(ir.expires_at) or ir.expires_at > ^now
    )
    |> Repo.exists?()
  end

  # ── Role Management ────────────────────────────────────────────────

  @doc "Assign a role to an identity by role name."
  def assign_role(identity_id, role_name, granted_by, opts \\ []) do
    expires_at = Keyword.get(opts, :expires_at)

    with {:ok, role} <- get_role(role_name) do
      attrs = %{
        identity_id: identity_id,
        role_id: role.id,
        granted_by: granted_by,
        granted_at: DateTime.utc_now() |> DateTime.truncate(:microsecond),
        expires_at: expires_at
      }

      result =
        %IdentityRole{}
        |> IdentityRole.changeset(attrs)
        |> Repo.insert(
          on_conflict: :nothing,
          conflict_target: [:identity_id, :role_id]
        )

      # Sync is_admin flag
      sync_admin_flag(identity_id)

      result
    end
  end

  @doc "Revoke a role from an identity by role name."
  def revoke_role(identity_id, role_name, _revoked_by) do
    with {:ok, role} <- get_role(role_name) do
      {count, _} =
        from(ir in IdentityRole,
          where: ir.identity_id == ^identity_id and ir.role_id == ^role.id
        )
        |> Repo.delete_all()

      # Sync is_admin flag
      sync_admin_flag(identity_id)

      if count > 0, do: {:ok, :revoked}, else: {:error, :not_found}
    end
  end

  @doc "Get all active role names for an identity."
  def get_roles(identity_id) do
    now = DateTime.utc_now()

    from(ir in IdentityRole,
      join: r in Role,
      on: ir.role_id == r.id,
      where: ir.identity_id == ^identity_id,
      where: is_nil(ir.expires_at) or ir.expires_at > ^now,
      select: r.name
    )
    |> Repo.all()
  end

  @doc "Get all active permissions for an identity (flat list of names)."
  def get_permissions(identity_id) do
    now = DateTime.utc_now()

    from(ir in IdentityRole,
      join: r in Role,
      on: ir.role_id == r.id,
      join: rp in RolePermission,
      on: rp.role_id == r.id,
      join: p in Permission,
      on: rp.permission_id == p.id,
      where: ir.identity_id == ^identity_id,
      where: is_nil(ir.expires_at) or ir.expires_at > ^now,
      select: p.name,
      distinct: true
    )
    |> Repo.all()
  end

  # ── Role CRUD ──────────────────────────────────────────────────────

  @doc "List all roles with their permissions."
  def list_roles do
    Role
    |> order_by([r], asc: r.name)
    |> Repo.all()
    |> Repo.preload(:permissions)
  end

  @doc "Get a role by name."
  def get_role(name) when is_binary(name) do
    case Repo.get_by(Role, name: name) do
      nil -> {:error, :role_not_found}
      role -> {:ok, role}
    end
  end

  @doc "Get a role by id."
  def get_role_by_id(id) do
    case Repo.get(Role, id) do
      nil -> {:error, :role_not_found}
      role -> {:ok, role |> Repo.preload(:permissions)}
    end
  end

  @doc "Create a custom (non-system) role."
  def create_role(attrs) do
    %Role{}
    |> Role.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc "Update a role."
  def update_role(id, attrs) do
    with {:ok, role} <- get_role_by_id(id) do
      role
      |> Role.update_changeset(attrs)
      |> Repo.update()
    end
  end

  @doc "Delete a role. System roles cannot be deleted."
  def delete_role(id) do
    with {:ok, role} <- get_role_by_id(id) do
      if role.is_system do
        {:error, :cannot_delete_system_role}
      else
        Repo.delete(role)
      end
    end
  end

  # ── Permission Listing ─────────────────────────────────────────────

  @doc "List all permissions."
  def list_permissions do
    Permission
    |> order_by([p], asc: p.category, asc: p.name)
    |> Repo.all()
  end

  @doc "List permissions grouped by category."
  def list_permissions_by_category do
    list_permissions()
    |> Enum.group_by(& &1.category)
  end

  # ── Role-Permission Management ─────────────────────────────────────

  @doc "Add a permission to a role."
  def add_permission_to_role(role_id, permission_id) do
    %RolePermission{}
    |> RolePermission.changeset(%{role_id: role_id, permission_id: permission_id})
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:role_id, :permission_id])
  end

  @doc "Remove a permission from a role."
  def remove_permission_from_role(role_id, permission_id) do
    {count, _} =
      from(rp in RolePermission,
        where: rp.role_id == ^role_id and rp.permission_id == ^permission_id
      )
      |> Repo.delete_all()

    if count > 0, do: {:ok, :removed}, else: {:error, :not_found}
  end

  @doc "Get all permissions for a role."
  def get_role_permissions(role_id) do
    from(p in Permission,
      join: rp in RolePermission,
      on: rp.permission_id == p.id,
      where: rp.role_id == ^role_id,
      order_by: [asc: p.category, asc: p.name]
    )
    |> Repo.all()
  end

  # ── Identity Role Management (for admin API) ──────────────────────

  @doc "Get identity roles with role details."
  def get_identity_roles(identity_id) do
    now = DateTime.utc_now()

    from(ir in IdentityRole,
      join: r in Role,
      on: ir.role_id == r.id,
      where: ir.identity_id == ^identity_id,
      where: is_nil(ir.expires_at) or ir.expires_at > ^now,
      preload: [role: r]
    )
    |> Repo.all()
  end

  @doc "Revoke a role from an identity by identity_role id."
  def revoke_role_by_id(identity_role_id) do
    case Repo.get(IdentityRole, identity_role_id) do
      nil ->
        {:error, :not_found}

      identity_role ->
        result = Repo.delete(identity_role)
        sync_admin_flag(identity_role.identity_id)
        result
    end
  end

  # ── Setup ──────────────────────────────────────────────────────────

  @doc """
  Assigns the 'owner' role to an identity.
  Only works if no owner exists yet.
  """
  def setup_owner(identity_id) do
    with {:ok, role} <- get_role("owner") do
      existing_owner =
        from(ir in IdentityRole,
          where: ir.role_id == ^role.id,
          limit: 1
        )
        |> Repo.one()

      if existing_owner do
        {:error, :owner_already_exists}
      else
        assign_role(identity_id, "owner", identity_id)
      end
    end
  end

  # ── Private ────────────────────────────────────────────────────────

  defp sync_admin_flag(identity_id) do
    is_staff = is_staff?(identity_id)

    from(i in Hybridsocial.Accounts.Identity,
      where: i.id == ^identity_id
    )
    |> Repo.update_all(set: [is_admin: is_staff])
  end
end
