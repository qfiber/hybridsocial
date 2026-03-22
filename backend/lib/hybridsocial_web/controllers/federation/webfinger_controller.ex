defmodule HybridsocialWeb.Federation.WebfingerController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Federation.WebFinger

  def show(conn, %{"resource" => resource}) do
    case WebFinger.resolve_local(resource) do
      {:ok, identity} ->
        jrd = WebFinger.represent(identity)

        conn
        |> put_resp_content_type("application/jrd+json")
        |> json(jrd)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Not found"})

      {:error, :not_local} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Not a local user"})

      {:error, :invalid_resource} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid resource"})
    end
  end

  def show(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing resource parameter"})
  end
end
