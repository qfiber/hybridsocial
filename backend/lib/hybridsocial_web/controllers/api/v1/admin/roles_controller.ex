defmodule HybridsocialWeb.Api.V1.Admin.RolesController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Auth.RBAC

  defp require_permission(conn, permission) do
    identity = conn.assigns.current_identity

    if RBAC.has_permission?(identity.id, permission) do
      :ok
    else
      {:error, permission}
    end
  end

  defp deny(conn, permission) do
    conn
    |> put_status(:forbidden)
    |> json(%{error: "permission.denied", required: permission})
  end

  # ── Role CRUD ──────────────────────────────────────────────────────

  def index(conn, _params) do
    with :ok <- require_permission(conn, "roles.view") do
      roles = RBAC.list_roles()

      conn
      |> put_status(:ok)
      |> json(%{data: Enum.map(roles, &serialize_role/1)})
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def create(conn, params) do
    with :ok <- require_permission(conn, "roles.manage") do
      case RBAC.create_role(params) do
        {:ok, role} ->
          role = Hybridsocial.Repo.preload(role, :permissions)
          conn |> put_status(:created) |> json(%{data: serialize_role(role)})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "validation.failed", details: format_errors(changeset)})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def update(conn, %{"id" => id} = params) do
    with :ok <- require_permission(conn, "roles.manage") do
      case RBAC.update_role(id, params) do
        {:ok, role} ->
          role = Hybridsocial.Repo.preload(role, :permissions)
          conn |> put_status(:ok) |> json(%{data: serialize_role(role)})

        {:error, :role_not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "role.not_found"})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "validation.failed", details: format_errors(changeset)})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def delete(conn, %{"id" => id}) do
    with :ok <- require_permission(conn, "roles.manage") do
      case RBAC.delete_role(id) do
        {:ok, _} ->
          conn |> put_status(:ok) |> json(%{message: "role.deleted"})

        {:error, :role_not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "role.not_found"})

        {:error, :cannot_delete_system_role} ->
          conn |> put_status(:forbidden) |> json(%{error: "role.cannot_delete_system"})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  # ── Role Permissions ───────────────────────────────────────────────

  def permissions(conn, %{"id" => id}) do
    with :ok <- require_permission(conn, "roles.view") do
      permissions = RBAC.get_role_permissions(id)

      conn
      |> put_status(:ok)
      |> json(%{data: Enum.map(permissions, &serialize_permission/1)})
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def add_permission(conn, %{"id" => role_id, "permission_id" => permission_id}) do
    with :ok <- require_permission(conn, "roles.manage") do
      case RBAC.add_permission_to_role(role_id, permission_id) do
        {:ok, _} ->
          conn |> put_status(:created) |> json(%{message: "permission.added"})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "validation.failed", details: format_errors(changeset)})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def remove_permission(conn, %{"id" => role_id, "pid" => permission_id}) do
    with :ok <- require_permission(conn, "roles.manage") do
      case RBAC.remove_permission_from_role(role_id, permission_id) do
        {:ok, :removed} ->
          conn |> put_status(:ok) |> json(%{message: "permission.removed"})

        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "permission.not_found"})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  # ── User Role Assignment ──────────────────────────────────────────

  def assign_role(conn, %{"user_id" => user_id, "role_id" => role_id} = params) do
    with :ok <- require_permission(conn, "roles.manage") do
      granted_by = conn.assigns.current_identity.id

      # Look up role name from role_id
      case RBAC.get_role_by_id(role_id) do
        {:ok, role} ->
          opts =
            case params["expires_at"] do
              nil ->
                []

              expires_at_str ->
                case DateTime.from_iso8601(expires_at_str) do
                  {:ok, dt, _} -> [expires_at: dt]
                  _ -> []
                end
            end

          case RBAC.assign_role(user_id, role.name, granted_by, opts) do
            {:ok, identity_role} ->
              conn
              |> put_status(:created)
              |> json(%{data: serialize_identity_role(identity_role)})

            {:error, changeset} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{error: "validation.failed", details: format_errors(changeset)})
          end

        {:error, :role_not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "role.not_found"})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def revoke_role(conn, %{"user_id" => _user_id, "role_id" => identity_role_id}) do
    with :ok <- require_permission(conn, "roles.manage") do
      case RBAC.revoke_role_by_id(identity_role_id) do
        {:ok, _} ->
          conn |> put_status(:ok) |> json(%{message: "role.revoked"})

        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "role.not_found"})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  # ── All Permissions listing ────────────────────────────────────────

  def list_all_permissions(conn, _params) do
    with :ok <- require_permission(conn, "roles.view") do
      permissions_by_category = RBAC.list_permissions_by_category()

      data =
        Enum.map(permissions_by_category, fn {category, perms} ->
          %{
            category: category,
            permissions: Enum.map(perms, &serialize_permission/1)
          }
        end)

      conn
      |> put_status(:ok)
      |> json(%{data: data})
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  # ── Serializers ────────────────────────────────────────────────────

  defp serialize_role(role) do
    %{
      id: role.id,
      name: role.name,
      description: role.description,
      is_system: role.is_system,
      permissions: Enum.map(role.permissions, &serialize_permission/1),
      created_at: role.inserted_at
    }
  end

  defp serialize_permission(permission) do
    %{
      id: permission.id,
      name: permission.name,
      description: permission.description,
      category: permission.category
    }
  end

  defp serialize_identity_role(identity_role) do
    %{
      id: identity_role.id,
      identity_id: identity_role.identity_id,
      role_id: identity_role.role_id,
      granted_by: identity_role.granted_by,
      granted_at: identity_role.granted_at,
      expires_at: identity_role.expires_at
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
