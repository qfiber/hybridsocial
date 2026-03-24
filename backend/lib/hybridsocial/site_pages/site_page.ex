defmodule Hybridsocial.SitePages.SitePage do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "site_pages" do
    field :slug, :string
    field :title, :string
    field :body_markdown, :string, default: ""
    field :body_html, :string, default: ""
    field :published, :boolean, default: false
    field :last_edited_by, :binary_id
    field :deleted_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @allowed_slugs ~w(privacy terms about)

  def changeset(page, attrs) do
    page
    |> cast(attrs, [:slug, :title, :body_markdown, :published, :last_edited_by])
    |> validate_required([:slug, :title])
    |> validate_length(:title, max: 100)
    |> validate_length(:body_markdown, max: 50_000)
    |> validate_inclusion(:slug, @allowed_slugs, message: "must be one of: #{Enum.join(@allowed_slugs, ", ")}")
    |> unique_constraint(:slug)
    |> render_markdown()
  end

  defp render_markdown(changeset) do
    case get_change(changeset, :body_markdown) do
      nil ->
        changeset

      markdown ->
        html = markdown_to_html(markdown)
        put_change(changeset, :body_html, html)
    end
  end

  defp markdown_to_html(""), do: ""

  defp markdown_to_html(markdown) do
    markdown
    |> String.trim()
    |> simple_markdown_to_html()
  end

  # Simple markdown-to-HTML converter that handles common formatting
  defp simple_markdown_to_html(text) do
    text
    |> String.split("\n\n", trim: true)
    |> Enum.map(&process_block/1)
    |> Enum.join("\n")
  end

  defp process_block(block) do
    block = String.trim(block)

    cond do
      String.starts_with?(block, "### ") ->
        content = String.trim_leading(block, "### ") |> escape_html() |> inline_formatting()
        "<h3>#{content}</h3>"

      String.starts_with?(block, "## ") ->
        content = String.trim_leading(block, "## ") |> escape_html() |> inline_formatting()
        "<h2>#{content}</h2>"

      String.starts_with?(block, "# ") ->
        content = String.trim_leading(block, "# ") |> escape_html() |> inline_formatting()
        "<h1>#{content}</h1>"

      String.starts_with?(block, "- ") or String.starts_with?(block, "* ") ->
        items =
          block
          |> String.split("\n")
          |> Enum.map(fn line ->
            content = String.replace(line, ~r/^[\-\*]\s+/, "") |> escape_html() |> inline_formatting()
            "<li>#{content}</li>"
          end)
          |> Enum.join("\n")

        "<ul>\n#{items}\n</ul>"

      true ->
        content =
          block
          |> String.split("\n")
          |> Enum.map(&escape_html/1)
          |> Enum.join("<br>")
          |> inline_formatting()

        "<p>#{content}</p>"
    end
  end

  defp inline_formatting(text) do
    text
    |> String.replace(~r/\*\*(.+?)\*\*/, "<strong>\\1</strong>")
    |> String.replace(~r/\*(.+?)\*/, "<em>\\1</em>")
    |> String.replace(~r/`(.+?)`/, "<code>\\1</code>")
    |> String.replace(~r/\[(.+?)\]\((.+?)\)/, "<a href=\"\\2\" rel=\"noopener noreferrer\">\\1</a>")
  end

  defp escape_html(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
