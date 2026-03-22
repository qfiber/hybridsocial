defmodule HybridsocialWeb.Api.V1.PageController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Pages

  # ---------------------------------------------------------------------------
  # Page CRUD
  # ---------------------------------------------------------------------------

  @doc "POST /api/v1/pages"
  def create(conn, params) do
    identity = conn.assigns.current_identity

    case Pages.create_page(identity.id, params) do
      {:ok, page} ->
        conn
        |> put_status(:created)
        |> json(serialize_page(page))

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  @doc "GET /api/v1/pages"
  def index(conn, params) do
    opts = [
      limit: to_integer(params["limit"], 20),
      offset: to_integer(params["offset"], 0)
    ]

    pages = Pages.list_pages(opts)
    json(conn, Enum.map(pages, &serialize_page/1))
  end

  @doc "GET /api/v1/pages/:id"
  def show(conn, %{"id" => id}) do
    case Pages.get_page(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "page.not_found"})

      page ->
        branding = Pages.get_branding(id)
        json(conn, serialize_page(page, branding))
    end
  end

  @doc "PATCH /api/v1/pages/:id"
  def update(conn, %{"id" => id} = params) do
    identity = conn.assigns.current_identity

    case Pages.update_page(id, identity.id, params) do
      {:ok, page} ->
        json(conn, serialize_page(page))

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "page.not_found"})

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "page.forbidden"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  @doc "DELETE /api/v1/pages/:id"
  def delete(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity

    case Pages.delete_page(id, identity.id) do
      {:ok, _} ->
        send_resp(conn, :no_content, "")

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "page.not_found"})

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "page.forbidden"})
    end
  end

  # ---------------------------------------------------------------------------
  # Roles
  # ---------------------------------------------------------------------------

  @doc "GET /api/v1/pages/:id/roles"
  def roles(conn, %{"id" => id}) do
    roles = Pages.get_roles(id)
    json(conn, Enum.map(roles, &serialize_role/1))
  end

  @doc "POST /api/v1/pages/:id/roles"
  def add_role(conn, %{"id" => id} = params) do
    identity = conn.assigns.current_identity
    target_id = params["identity_id"]
    role = params["role"]

    case Pages.add_role(id, identity.id, target_id, role) do
      {:ok, org_role} ->
        conn
        |> put_status(:created)
        |> json(serialize_role(org_role))

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "page.not_found"})

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "page.forbidden"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  @doc "DELETE /api/v1/pages/:id/roles/:role_id"
  def remove_role(conn, %{"id" => id, "role_id" => role_id}) do
    identity = conn.assigns.current_identity

    case Pages.remove_role(id, identity.id, role_id) do
      {:ok, _} ->
        send_resp(conn, :no_content, "")

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "role.not_found"})

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "page.forbidden"})
    end
  end

  # ---------------------------------------------------------------------------
  # Branding
  # ---------------------------------------------------------------------------

  @doc "GET /api/v1/pages/:id/branding"
  def branding(conn, %{"id" => id}) do
    case Pages.get_branding(id) do
      nil ->
        json(conn, %{identity_id: id, theme_color: nil, cover_image_url: nil, custom_css: nil, logo_url: nil, layout_preference: %{}})

      branding ->
        json(conn, serialize_branding(branding))
    end
  end

  @doc "PATCH /api/v1/pages/:id/branding"
  def update_branding(conn, %{"id" => id} = params) do
    identity = conn.assigns.current_identity
    attrs = Map.take(params, ["theme_color", "cover_image_url", "custom_css", "logo_url", "layout_preference"])

    case Pages.update_branding(id, identity.id, attrs) do
      {:ok, branding} ->
        json(conn, serialize_branding(branding))

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "page.not_found"})

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "page.forbidden"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  # ---------------------------------------------------------------------------
  # Serializers
  # ---------------------------------------------------------------------------

  defp serialize_page(page, branding \\ nil) do
    base = %{
      id: page.id,
      type: page.type,
      handle: page.handle,
      display_name: page.display_name,
      bio: page.bio,
      avatar_url: page.avatar_url,
      header_url: page.header_url,
      is_locked: page.is_locked,
      is_bot: page.is_bot,
      created_at: page.inserted_at,
      organization: serialize_org(page.organization)
    }

    if branding do
      Map.put(base, :branding, serialize_branding(branding))
    else
      base
    end
  end

  defp serialize_org(nil), do: nil

  defp serialize_org(org) do
    %{
      owner_id: org.owner_id,
      website: org.website,
      category: org.category
    }
  end

  defp serialize_role(role) do
    %{
      id: role.id,
      organization_id: role.organization_id,
      identity_id: role.identity_id,
      role: role.role,
      granted_by: role.granted_by,
      created_at: role.inserted_at
    }
  end

  defp serialize_branding(branding) do
    %{
      identity_id: branding.identity_id,
      theme_color: branding.theme_color,
      cover_image_url: branding.cover_image_url,
      custom_css: branding.custom_css,
      logo_url: branding.logo_url,
      layout_preference: branding.layout_preference,
      updated_at: branding.updated_at
    }
  end

  defp to_integer(nil, default), do: default
  defp to_integer(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> default
    end
  end
  defp to_integer(val, _default) when is_integer(val), do: val

  defp format_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
