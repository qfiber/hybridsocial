defmodule HybridsocialWeb.Api.V1.DirectoryController do
  use HybridsocialWeb, :controller

  import Ecto.Query

  alias Hybridsocial.Repo
  alias Hybridsocial.Accounts.Identity
  alias Hybridsocial.Accounts.User

  @doc """
  GET /api/v1/directory/new — Returns recently joined & confirmed users.
  Only shows local, non-suspended, non-bot identities with confirmed email.
  """
  def new_users(conn, params) do
    limit = min(parse_int(params["limit"], 8), 20)

    users =
      Identity
      |> where([i], i.type == "user")
      |> where([i], is_nil(i.deleted_at))
      |> where([i], i.is_suspended == false)
      |> where([i], i.is_shadow_banned == false)
      |> where([i], is_nil(i.parent_identity_id))
      |> join(:inner, [i], u in User, on: u.identity_id == i.id)
      |> where([i, u], not is_nil(u.confirmed_at))
      |> order_by([i, u], desc: u.confirmed_at)
      |> limit(^limit)
      |> select([i, u], %{
        id: i.id,
        handle: i.handle,
        display_name: i.display_name,
        avatar_url: i.avatar_url,
        bio: i.bio,
        joined_at: u.confirmed_at
      })
      |> Repo.all()

    json(conn, users)
  end

  defp parse_int(nil, default), do: default
  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> default
    end
  end
  defp parse_int(val, _) when is_integer(val), do: val
end
