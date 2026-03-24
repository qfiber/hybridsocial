defmodule HybridsocialWeb.Api.V1.Admin.SitePagesController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.SitePages
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

  def index(conn, _params) do
    with :ok <- require_permission(conn, "settings.view") do
      pages = SitePages.list_pages()
      json(conn, %{data: Enum.map(pages, &serialize/1)})
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def show(conn, %{"id" => id}) do
    with :ok <- require_permission(conn, "settings.view") do
      case SitePages.get_page(id) do
        nil ->
          conn |> put_status(:not_found) |> json(%{error: "page.not_found"})

        page ->
          json(conn, %{data: serialize(page)})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def update(conn, %{"id" => id} = params) do
    with :ok <- require_permission(conn, "settings.manage") do
      admin_id = conn.assigns.current_identity.id

      case SitePages.get_page(id) do
        nil ->
          conn |> put_status(:not_found) |> json(%{error: "page.not_found"})

        page ->
          attrs = Map.take(params, ["title", "body_markdown", "published"])

          case SitePages.update_page(page, attrs, admin_id) do
            {:ok, updated} ->
              json(conn, %{data: serialize(updated)})

            {:error, changeset} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{error: "validation.failed", details: format_errors(changeset)})
          end
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def seed(conn, _params) do
    with :ok <- require_permission(conn, "settings.manage") do
      SitePages.ensure_defaults()
      pages = SitePages.list_pages()
      json(conn, %{data: Enum.map(pages, &serialize/1)})
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  defp serialize(page) do
    %{
      id: page.id,
      slug: page.slug,
      title: page.title,
      body_markdown: page.body_markdown,
      body_html: page.body_html,
      published: page.published,
      last_edited_by: page.last_edited_by,
      updated_at: page.updated_at,
      created_at: page.inserted_at
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
