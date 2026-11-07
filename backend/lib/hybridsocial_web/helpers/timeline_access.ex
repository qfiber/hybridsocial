defmodule HybridsocialWeb.Helpers.TimelineAccess do
  @moduledoc """
  What anonymous visitors may read, from the `public_timeline_access` setting.
  Logged-in members are never limited by it.

    * `"all"`: everything
    * `"local"`: this instance's content only
    * `"none"`: nothing, log in first
  """
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Hybridsocial.Config

  def level, do: Config.get("public_timeline_access", "all")

  @doc "`:ok` or `:denied`, for a route serving `:local` or `:global` content."
  def check(conn, content) do
    cond do
      logged_in?(conn) -> :ok
      level() == "none" -> :denied
      level() == "local" and content == :global -> :denied
      true -> :ok
    end
  end

  @doc "Whether this request may only be shown this instance's content."
  def local_only?(conn), do: not logged_in?(conn) and level() == "local"

  def deny(conn) do
    conn
    |> put_status(:unauthorized)
    |> json(%{
      error: "timeline.login_required",
      message: "You need to create an account to view this timeline."
    })
    |> halt()
  end

  defp logged_in?(conn), do: conn.assigns[:current_identity] != nil
end
