defmodule Hybridsocial.Social.Lists do
  @moduledoc """
  Context module for managing user lists and list membership.
  """
  import Ecto.Query

  alias Hybridsocial.Repo
  alias Hybridsocial.Social.{List, ListMember}

  # ---------------------------------------------------------------------------
  # List CRUD
  # ---------------------------------------------------------------------------

  @doc """
  Creates a new list for the given identity.
  """
  def create_list(identity_id, name) do
    %List{}
    |> List.changeset(%{identity_id: identity_id, name: name})
    |> Repo.insert()
  end

  @doc """
  Updates a list. Only the owner can update.
  """
  def update_list(list_id, identity_id, attrs) do
    case get_owned_list(list_id, identity_id) do
      nil ->
        {:error, :not_found}

      list ->
        list
        |> List.update_changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Deletes a list. Only the owner can delete.
  """
  def delete_list(list_id, identity_id) do
    case get_owned_list(list_id, identity_id) do
      nil -> {:error, :not_found}
      list -> Repo.delete(list)
    end
  end

  @doc """
  Gets a list by ID.
  """
  def get_list(id) do
    Repo.get(List, id)
  end

  @doc """
  Gets all lists for a given identity.
  """
  def get_lists(identity_id) do
    List
    |> where([l], l.identity_id == ^identity_id)
    |> order_by([l], asc: l.name)
    |> Repo.all()
  end

  # ---------------------------------------------------------------------------
  # Membership
  # ---------------------------------------------------------------------------

  @doc """
  Adds a target identity to a list. Only the list owner can add members.
  """
  def add_to_list(list_id, identity_id, target_id) do
    case get_owned_list(list_id, identity_id) do
      nil ->
        {:error, :not_found}

      _list ->
        %ListMember{}
        |> ListMember.changeset(%{list_id: list_id, target_identity_id: target_id})
        |> Repo.insert()
    end
  end

  @doc """
  Removes a target identity from a list. Only the list owner can remove members.
  """
  def remove_from_list(list_id, identity_id, target_id) do
    case get_owned_list(list_id, identity_id) do
      nil ->
        {:error, :not_found}

      _list ->
        ListMember
        |> where([lm], lm.list_id == ^list_id and lm.target_identity_id == ^target_id)
        |> Repo.delete_all()

        :ok
    end
  end

  @doc """
  Returns all members of a list.
  """
  def list_members(list_id) do
    ListMember
    |> where([lm], lm.list_id == ^list_id)
    |> preload(:target_identity)
    |> Repo.all()
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp get_owned_list(list_id, identity_id) do
    List
    |> where([l], l.id == ^list_id and l.identity_id == ^identity_id)
    |> Repo.one()
  end
end
