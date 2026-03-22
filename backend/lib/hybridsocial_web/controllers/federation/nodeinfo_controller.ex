defmodule HybridsocialWeb.Federation.NodeinfoController do
  use HybridsocialWeb, :controller

  def well_known(conn, _params) do
    base = HybridsocialWeb.Endpoint.url()

    jrd = %{
      links: [
        %{
          rel: "http://nodeinfo.diaspora.software/ns/schema/2.0",
          href: "#{base}/nodeinfo/2.0"
        }
      ]
    }

    conn
    |> put_resp_content_type("application/json")
    |> json(jrd)
  end

  def show(conn, _params) do
    conn
    |> put_resp_content_type("application/json")
    |> json(Hybridsocial.Instance.nodeinfo())
  end
end
