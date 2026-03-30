defmodule HybridsocialWeb.Api.V1.InstanceController do
  use HybridsocialWeb, :controller

  def show(conn, _params) do
    json(conn, Hybridsocial.Instance.info())
  end

  def online_count(conn, _params) do
    import Ecto.Query

    cutoff = DateTime.add(DateTime.utc_now(), -300, :second)
    count =
      from(u in "users", where: u.last_login_at > ^cutoff, select: count(u.identity_id))
      |> Hybridsocial.Repo.one() || 0

    json(conn, %{count: count})
  end
end
