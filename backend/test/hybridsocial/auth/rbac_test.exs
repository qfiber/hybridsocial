defmodule Hybridsocial.Auth.RBACTest do
  use Hybridsocial.DataCase

  alias Hybridsocial.Auth.RBAC

  defp create_user(handle, email) do
    {:ok, identity} =
      Hybridsocial.Accounts.register_user(%{
        "handle" => handle,
        "email" => email,
        "password" => "password123",
        "password_confirmation" => "password123"
      })

    identity
  end

  defp make_admin(identity) do
    {:ok, _} = RBAC.assign_role(identity.id, "owner", identity.id)
    identity
  end

  describe "has_permission?/2" do
    test "returns true when identity has the permission through a role" do
      user = create_user("perm1", "perm1@test.com")
      make_admin(user)

      assert RBAC.has_permission?(user.id, "users.view")
      assert RBAC.has_permission?(user.id, "reports.manage")
    end

    test "returns false when identity does not have the permission" do
      user = create_user("perm2", "perm2@test.com")

      refute RBAC.has_permission?(user.id, "users.view")
    end

    test "returns false when role has expired" do
      user = create_user("perm3", "perm3@test.com")
      past = DateTime.add(DateTime.utc_now(), -3600, :second)

      {:ok, _} = RBAC.assign_role(user.id, "moderator", user.id, expires_at: past)

      refute RBAC.has_permission?(user.id, "reports.view")
    end

    test "returns true when role has not yet expired" do
      user = create_user("perm4", "perm4@test.com")
      future = DateTime.add(DateTime.utc_now(), 3600, :second)

      {:ok, _} = RBAC.assign_role(user.id, "moderator", user.id, expires_at: future)

      assert RBAC.has_permission?(user.id, "reports.view")
    end
  end

  describe "has_any_permission?/2" do
    test "returns true when identity has at least one of the permissions" do
      user = create_user("any1", "any1@test.com")
      {:ok, _} = RBAC.assign_role(user.id, "moderator", user.id)

      assert RBAC.has_any_permission?(user.id, ["users.view", "settings.edit"])
    end

    test "returns false when identity has none of the permissions" do
      user = create_user("any2", "any2@test.com")

      refute RBAC.has_any_permission?(user.id, ["users.view", "settings.edit"])
    end
  end

  describe "has_all_permissions?/2" do
    test "returns true when identity has all permissions" do
      user = create_user("all1", "all1@test.com")
      make_admin(user)

      assert RBAC.has_all_permissions?(user.id, ["users.view", "reports.view"])
    end

    test "returns false when identity is missing some permissions" do
      user = create_user("all2", "all2@test.com")
      {:ok, _} = RBAC.assign_role(user.id, "community_manager", user.id)

      refute RBAC.has_all_permissions?(user.id, ["users.view", "reports.view"])
    end
  end

  describe "is_staff?/1" do
    test "returns true when identity has any role" do
      user = create_user("staff1", "staff1@test.com")
      {:ok, _} = RBAC.assign_role(user.id, "moderator", user.id)

      assert RBAC.is_staff?(user.id)
    end

    test "returns false when identity has no roles" do
      user = create_user("staff2", "staff2@test.com")

      refute RBAC.is_staff?(user.id)
    end
  end

  describe "assign_role/4 and revoke_role/3" do
    test "assigns and revokes a role" do
      user = create_user("ar1", "ar1@test.com")
      {:ok, _} = RBAC.assign_role(user.id, "moderator", user.id)

      assert "moderator" in RBAC.get_roles(user.id)

      {:ok, :revoked} = RBAC.revoke_role(user.id, "moderator", user.id)

      refute "moderator" in RBAC.get_roles(user.id)
    end

    test "duplicate assignment is idempotent" do
      user = create_user("ar2", "ar2@test.com")
      {:ok, _} = RBAC.assign_role(user.id, "moderator", user.id)
      {:ok, _} = RBAC.assign_role(user.id, "moderator", user.id)

      assert RBAC.get_roles(user.id) == ["moderator"]
    end
  end

  describe "get_roles/1 and get_permissions/1" do
    test "returns correct roles and permissions" do
      user = create_user("gp1", "gp1@test.com")
      {:ok, _} = RBAC.assign_role(user.id, "moderator", user.id)

      roles = RBAC.get_roles(user.id)
      assert "moderator" in roles

      permissions = RBAC.get_permissions(user.id)
      assert "reports.view" in permissions
      assert "reports.manage" in permissions
      assert "users.view" in permissions
      refute "settings.edit" in permissions
    end
  end

  describe "role CRUD" do
    test "create, update, and delete a custom role" do
      {:ok, role} = RBAC.create_role(%{"name" => "tester", "description" => "Test role"})
      assert role.name == "tester"
      refute role.is_system

      {:ok, updated} = RBAC.update_role(role.id, %{"description" => "Updated"})
      assert updated.description == "Updated"

      {:ok, _} = RBAC.delete_role(role.id)
      assert {:error, :role_not_found} = RBAC.get_role_by_id(role.id)
    end

    test "cannot delete system roles" do
      {:ok, role} = RBAC.get_role("owner")
      assert {:error, :cannot_delete_system_role} = RBAC.delete_role(role.id)
    end
  end

  describe "role permission management" do
    test "add and remove permissions from a role" do
      {:ok, role} = RBAC.create_role(%{"name" => "custom1", "description" => "Custom"})

      permissions = RBAC.list_permissions()
      perm = hd(permissions)

      {:ok, _} = RBAC.add_permission_to_role(role.id, perm.id)
      role_perms = RBAC.get_role_permissions(role.id)
      assert length(role_perms) == 1
      assert hd(role_perms).id == perm.id

      {:ok, :removed} = RBAC.remove_permission_from_role(role.id, perm.id)
      assert RBAC.get_role_permissions(role.id) == []
    end
  end

  describe "setup_owner/1" do
    test "assigns owner role when no owner exists" do
      user = create_user("owner1", "owner1@test.com")

      # First, remove any existing owner assignments from migration
      {:ok, owner_role} = RBAC.get_role("owner")

      Hybridsocial.Repo.delete_all(
        from(ir in Hybridsocial.Auth.IdentityRole, where: ir.role_id == ^owner_role.id)
      )

      {:ok, _} = RBAC.setup_owner(user.id)
      assert "owner" in RBAC.get_roles(user.id)
    end

    test "returns error when owner already exists" do
      user1 = create_user("owner2", "owner2@test.com")
      user2 = create_user("owner3", "owner3@test.com")

      {:ok, owner_role} = RBAC.get_role("owner")

      Hybridsocial.Repo.delete_all(
        from(ir in Hybridsocial.Auth.IdentityRole, where: ir.role_id == ^owner_role.id)
      )

      {:ok, _} = RBAC.setup_owner(user1.id)
      assert {:error, :owner_already_exists} = RBAC.setup_owner(user2.id)
    end
  end

  describe "is_admin sync" do
    test "sets is_admin true when role assigned, false when all revoked" do
      user = create_user("sync1", "sync1@test.com")
      refute user.is_admin

      {:ok, _} = RBAC.assign_role(user.id, "moderator", user.id)
      updated = Hybridsocial.Accounts.get_identity!(user.id)
      assert updated.is_admin

      {:ok, :revoked} = RBAC.revoke_role(user.id, "moderator", user.id)
      updated2 = Hybridsocial.Accounts.get_identity!(user.id)
      refute updated2.is_admin
    end
  end
end
