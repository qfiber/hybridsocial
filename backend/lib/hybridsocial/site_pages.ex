defmodule Hybridsocial.SitePages do
  @moduledoc """
  Context for managing admin-editable site pages (privacy policy, terms of service, about, etc.).
  Pages are written in Markdown and stored as both raw markdown and rendered HTML.
  """

  import Ecto.Query
  alias Hybridsocial.Repo
  alias Hybridsocial.SitePages.SitePage

  @doc "List all site pages (excluding soft-deleted)."
  def list_pages do
    SitePage
    |> where([p], is_nil(p.deleted_at))
    |> order_by([p], asc: p.slug)
    |> Repo.all()
  end

  @doc "Get a site page by slug (public — only published, non-deleted)."
  def get_published_page(slug) do
    SitePage
    |> where([p], p.slug == ^slug and p.published == true and is_nil(p.deleted_at))
    |> Repo.one()
  end

  @doc "Get a site page by id (admin)."
  def get_page(id) do
    SitePage
    |> where([p], p.id == ^id and is_nil(p.deleted_at))
    |> Repo.one()
  end

  @doc "Get a site page by slug (admin — any publish state)."
  def get_page_by_slug(slug) do
    SitePage
    |> where([p], p.slug == ^slug and is_nil(p.deleted_at))
    |> Repo.one()
  end

  @doc "Create a new site page."
  def create_page(attrs, editor_id) do
    %SitePage{}
    |> SitePage.changeset(attrs |> Map.put("last_edited_by", editor_id))
    |> Repo.insert()
  end

  @doc "Update an existing site page."
  def update_page(%SitePage{} = page, attrs, editor_id) do
    page
    |> SitePage.changeset(attrs |> Map.put("last_edited_by", editor_id))
    |> Repo.update()
  end

  @doc "Soft-delete a site page."
  def delete_page(%SitePage{} = page) do
    page
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now())
    |> Repo.update()
  end

  @placeholder "This page is a placeholder, update it as you wish."

  @doc "Seed default pages if they don't exist."
  def ensure_defaults do
    defaults = [
      %{slug: "privacy", title: "Privacy Policy"},
      %{slug: "terms", title: "Terms of Service"},
      %{slug: "about", title: "About This Server"}
    ]

    Enum.each(defaults, fn %{slug: slug, title: title} ->
      if is_nil(get_page_by_slug(slug)) do
        %SitePage{}
        |> SitePage.changeset(%{
          "slug" => slug,
          "title" => title,
          "body_markdown" => @placeholder,
          "published" => true
        })
        |> Repo.insert()
      end
    end)
  end
end
