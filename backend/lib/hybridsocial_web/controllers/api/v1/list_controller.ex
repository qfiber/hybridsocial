defmodule HybridsocialWeb.Api.V1.ListController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Social.Lists

  @doc "GET /api/v1/lists - All lists for the authenticated user"
  def index(conn, _params) do
    identity = conn.assigns.current_identity
    lists = Lists.get_lists(identity.id)
    json(conn, Enum.map(lists, &serialize_list/1))
  end

  @doc "POST /api/v1/lists - Create a new list"
  def create(conn, %{"name" => name}) do
    identity = conn.assigns.current_identity

    case Lists.create_list(identity.id, name) do
      {:ok, list} ->
        conn
        |> put_status(:created)
        |> json(serialize_list(list))

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Validation failed", details: format_errors(changeset)})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "name is required"})
  end

  @doc "GET /api/v1/lists/:id - Show a list"
  def show(conn, %{"id" => id}) do
    case Lists.get_list(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "List not found"})

      list ->
        json(conn, serialize_list(list))
    end
  end

  @doc "PATCH /api/v1/lists/:id - Update a list"
  def update(conn, %{"id" => id} = params) do
    identity = conn.assigns.current_identity
    attrs = Map.take(params, ["name"])

    case Lists.update_list(id, identity.id, attrs) do
      {:ok, list} ->
        json(conn, serialize_list(list))

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "List not found"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Validation failed", details: format_errors(changeset)})
    end
  end

  @doc "DELETE /api/v1/lists/:id - Delete a list"
  def delete(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity

    case Lists.delete_list(id, identity.id) do
      {:ok, _list} ->
        send_resp(conn, :no_content, "")

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "List not found"})
    end
  end

  @doc "GET /api/v1/lists/:id/accounts - List members"
  def accounts(conn, %{"id" => id}) do
    members = Lists.list_members(id)

    accounts =
      Enum.map(members, fn member ->
        serialize_account(member.target_identity)
      end)

    json(conn, accounts)
  end

  @doc "POST /api/v1/lists/:id/accounts - Add member(s) to list"
  def add_accounts(conn, %{"id" => id} = params) do
    identity = conn.assigns.current_identity
    account_ids = parse_account_ids(params)

    results =
      Enum.map(account_ids, fn target_id ->
        Lists.add_to_list(id, identity.id, target_id)
      end)

    errors = Enum.filter(results, fn
      {:error, _} -> true
      _ -> false
    end)

    if Enum.any?(errors, fn {:error, reason} -> reason == :not_found end) do
      conn |> put_status(:not_found) |> json(%{error: "List not found"})
    else
      send_resp(conn, :no_content, "")
    end
  end

  @doc "DELETE /api/v1/lists/:id/accounts - Remove member(s) from list"
  def remove_accounts(conn, %{"id" => id} = params) do
    identity = conn.assigns.current_identity
    account_ids = parse_account_ids(params)

    results =
      Enum.map(account_ids, fn target_id ->
        Lists.remove_from_list(id, identity.id, target_id)
      end)

    if Enum.any?(results, fn result -> result == {:error, :not_found} end) do
      conn |> put_status(:not_found) |> json(%{error: "List not found"})
    else
      send_resp(conn, :no_content, "")
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp parse_account_ids(params) do
    case params do
      %{"account_ids" => ids} when is_list(ids) -> ids
      %{"account_ids" => id} when is_binary(id) -> [id]
      _ -> []
    end
  end

  defp serialize_list(list) do
    %{
      id: list.id,
      name: list.name,
      created_at: list.inserted_at,
      updated_at: list.updated_at
    }
  end

  defp serialize_account(nil), do: nil

  defp serialize_account(identity) do
    %{
      id: identity.id,
      handle: identity.handle,
      display_name: identity.display_name,
      avatar_url: identity.avatar_url,
      header_url: identity.header_url,
      bio: identity.bio,
      is_bot: identity.is_bot,
      is_locked: identity.is_locked,
      created_at: identity.inserted_at
    }
  end

  defp format_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
