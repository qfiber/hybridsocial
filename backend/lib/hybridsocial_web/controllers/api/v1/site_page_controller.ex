defmodule HybridsocialWeb.Api.V1.SitePageController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.SitePages

  @valid_slugs ~w(privacy terms about)

  @default_titles %{
    "privacy" => "Privacy Policy",
    "terms" => "Terms of Service",
    "about" => "About This Server"
  }

  def show(conn, %{"slug" => slug}) when slug in @valid_slugs do
    case SitePages.get_page_by_slug(slug) do
      nil ->
        # Page not seeded yet — return a placeholder
        json(conn, %{
          data: %{
            slug: slug,
            title: @default_titles[slug],
            body_html: "",
            published: false,
            updated_at: nil
          }
        })

      page ->
        json(conn, %{
          data: %{
            slug: page.slug,
            title: page.title,
            body_html: page.body_html,
            published: page.published,
            updated_at: page.updated_at
          }
        })
    end
  end

  def show(conn, %{"slug" => _slug}) do
    conn |> put_status(:not_found) |> json(%{error: "page.not_found"})
  end
end
