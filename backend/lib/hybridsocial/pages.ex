defmodule Hybridsocial.Pages do
  @moduledoc """
  Context for managing organization pages, roles, and branding.
  """
  import Ecto.Query
  alias Hybridsocial.Repo
  alias Hybridsocial.Accounts.{Identity, Organization}
  alias Hybridsocial.Pages.{Branding, OrganizationRole}

  # ---------------------------------------------------------------------------
  # Page lifecycle
  # ---------------------------------------------------------------------------

  @doc "Creates an organization identity + organization record as a subaccount."
  def create_page(owner_identity_id, attrs) do
    with :ok <- Hybridsocial.Accounts.check_subaccount_limit(owner_identity_id, "organization") do
      Ecto.Multi.new()
      |> Ecto.Multi.insert(:identity, fn _ ->
        %Identity{}
        |> Identity.create_changeset(%{
          "type" => "organization",
          "handle" => attrs["handle"],
          "display_name" => attrs["display_name"],
          "bio" => attrs["bio"],
          "parent_identity_id" => owner_identity_id
        })
      end)
      |> Ecto.Multi.insert(:organization, fn %{identity: identity} ->
        %Organization{identity_id: identity.id}
        |> Organization.changeset(%{
          website: attrs["website"],
          category: attrs["category"]
        })
        |> Ecto.Changeset.put_change(:owner_id, owner_identity_id)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{identity: identity, organization: org}} ->
          page = %{identity | organization: org}
          Phoenix.PubSub.broadcast(Hybridsocial.PubSub, "identities", {:identity_created, page})
          {:ok, page}

        {:error, :identity, changeset, _} ->
          {:error, changeset}

        {:error, :organization, changeset, _} ->
          {:error, changeset}
      end
    end
  end

  @doc "Updates a page. Must be admin or owner."
  def update_page(page_identity_id, editor_id, attrs) do
    with {:ok, identity, _org} <- get_page_with_auth(page_identity_id),
         true <- can_edit?(page_identity_id, editor_id) do
      identity_attrs =
        Map.take(attrs, ["display_name", "bio", "avatar_url", "header_url"])

      org_attrs =
        Map.take(attrs, ["website", "category"])

      Ecto.Multi.new()
      |> Ecto.Multi.update(:identity, Identity.update_changeset(identity, identity_attrs))
      |> Ecto.Multi.update(:organization, fn %{identity: updated_identity} ->
        org = Repo.get!(Organization, updated_identity.id)
        Organization.changeset(org, org_attrs)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{identity: identity, organization: org}} ->
          page = %{identity | organization: org}
          Phoenix.PubSub.broadcast(Hybridsocial.PubSub, "identities", {:identity_updated, page})
          {:ok, page}

        {:error, _step, changeset, _} ->
          {:error, changeset}
      end
    else
      false -> {:error, :forbidden}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Soft deletes a page. Must be the owner."
  def delete_page(page_identity_id, owner_id) do
    with {:ok, identity, org} <- get_page_with_auth(page_identity_id),
         true <- org.owner_id == owner_id do
      case identity |> Identity.soft_delete_changeset() |> Repo.update() do
        {:ok, deleted} ->
          Phoenix.PubSub.broadcast(Hybridsocial.PubSub, "identities", {:identity_deleted, deleted.id})
          {:ok, deleted}
        error -> error
      end
    else
      false -> {:error, :forbidden}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Gets a page identity with its organization preloaded."
  def get_page(identity_id) do
    Identity
    |> where([i], i.id == ^identity_id and i.type == "organization" and is_nil(i.deleted_at))
    |> Repo.one()
    |> case do
      nil -> nil
      identity -> Repo.preload(identity, :organization)
    end
  end

  @doc "Lists all organization pages."
  def list_pages(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)

    Identity
    |> where([i], i.type == "organization" and is_nil(i.deleted_at))
    |> order_by([i], desc: i.inserted_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
    |> Repo.preload(:organization)
  end

  @doc "Lists all pages owned by the given identity."
  def pages_for_owner(owner_id) do
    Identity
    |> where([i], i.parent_identity_id == ^owner_id and i.type == "organization" and is_nil(i.deleted_at))
    |> order_by([i], asc: i.inserted_at)
    |> Repo.all()
    |> Repo.preload(:organization)
  end

  # ---------------------------------------------------------------------------
  # Roles
  # ---------------------------------------------------------------------------

  @doc "Adds a role. The granting identity must be admin or owner."
  def add_role(page_identity_id, admin_id, target_id, role) do
    with {:ok, _identity, org} <- get_page_with_auth(page_identity_id),
         true <- org.owner_id == admin_id or has_role?(page_identity_id, admin_id, ["admin"]) do
      %OrganizationRole{}
      |> OrganizationRole.changeset(%{
        organization_id: page_identity_id,
        identity_id: target_id,
        role: role,
        granted_by: admin_id
      })
      |> Repo.insert()
    else
      false -> {:error, :forbidden}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Removes a role by role id. The removing identity must be admin or owner."
  def remove_role(page_identity_id, admin_id, role_id) do
    with {:ok, _identity, org} <- get_page_with_auth(page_identity_id),
         true <- org.owner_id == admin_id or has_role?(page_identity_id, admin_id, ["admin"]) do
      case Repo.get(OrganizationRole, role_id) do
        nil ->
          {:error, :not_found}

        role ->
          if role.organization_id == page_identity_id do
            Repo.delete(role)
          else
            {:error, :not_found}
          end
      end
    else
      false -> {:error, :forbidden}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Lists all roles for a page."
  def get_roles(page_identity_id) do
    OrganizationRole
    |> where([r], r.organization_id == ^page_identity_id)
    |> Repo.all()
    |> Repo.preload(:identity)
  end

  @doc "Checks if the given identity has any of the specified roles."
  def has_role?(page_identity_id, identity_id, roles) do
    OrganizationRole
    |> where(
      [r],
      r.organization_id == ^page_identity_id and r.identity_id == ^identity_id and
        r.role in ^roles
    )
    |> Repo.exists?()
  end

  @doc "Checks if the identity can edit the page (parent owner, org owner, admin, or editor)."
  def can_edit?(page_identity_id, identity_id) do
    case get_page(page_identity_id) do
      nil ->
        false

      page_identity ->
        page_identity.parent_identity_id == identity_id or
          page_identity.organization.owner_id == identity_id or
          has_role?(page_identity_id, identity_id, ["admin", "editor"])
    end
  end

  # ---------------------------------------------------------------------------
  # Branding
  # ---------------------------------------------------------------------------

  @doc "Gets branding configuration for a page."
  def get_branding(page_identity_id) do
    Repo.get(Branding, page_identity_id)
  end

  @doc "Updates branding. Must be admin or owner."
  def update_branding(page_identity_id, admin_id, attrs) do
    with {:ok, _identity, org} <- get_page_with_auth(page_identity_id),
         true <- org.owner_id == admin_id or has_role?(page_identity_id, admin_id, ["admin"]) do
      branding =
        case Repo.get(Branding, page_identity_id) do
          nil -> %Branding{identity_id: page_identity_id}
          existing -> existing
        end

      branding
      |> Branding.changeset(attrs)
      |> Repo.insert_or_update()
    else
      false -> {:error, :forbidden}
      {:error, reason} -> {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp get_page_with_auth(page_identity_id) do
    case get_page(page_identity_id) do
      nil -> {:error, :not_found}
      identity -> {:ok, identity, identity.organization}
    end
  end
end
