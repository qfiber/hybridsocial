defmodule HybridsocialWeb.Api.V1.InstanceController do
  use HybridsocialWeb, :controller

  def show(conn, _params) do
    json(conn, Hybridsocial.Instance.info())
  end
end
