defmodule Hybridsocial.Social.Excerpts do
  @moduledoc "Context for Excerpts — user-created keyword-filtered feeds."

  import Ecto.Query
  alias Hybridsocial.Repo
  alias Hybridsocial.Social.{Excerpt, Post}

  def list_excerpts(identity_id) do
    Excerpt
    |> where([e], e.identity_id == ^identity_id)
    |> order_by([e], desc: e.inserted_at)
    |> Repo.all()
  end

  def get_excerpt(id, identity_id) do
    Excerpt
    |> where([e], e.id == ^id and e.identity_id == ^identity_id)
    |> Repo.one()
  end

  def create_excerpt(identity_id, attrs) do
    %Excerpt{}
    |> Excerpt.changeset(Map.put(attrs, "identity_id", identity_id))
    |> Repo.insert()
  end

  def update_excerpt(id, identity_id, attrs) do
    case get_excerpt(id, identity_id) do
      nil -> {:error, :not_found}
      excerpt ->
        excerpt
        |> Excerpt.changeset(attrs)
        |> Repo.update()
    end
  end

  def delete_excerpt(id, identity_id) do
    case get_excerpt(id, identity_id) do
      nil -> {:error, :not_found}
      excerpt -> Repo.delete(excerpt)
    end
  end

  @doc "Fetch posts matching an excerpt's keyword filters."
  def excerpt_feed(excerpt, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    max_id = Keyword.get(opts, :max_id)

    keywords = excerpt.keywords || []
    exclude = excerpt.exclude_keywords || []
    keyword_patterns = Enum.map(keywords, fn kw -> "%#{String.downcase(kw)}%" end)

    base =
      Post
      |> where([p], is_nil(p.deleted_at))
      |> where([p], p.visibility == "public")
      |> where([p], is_nil(p.parent_id))

    # Match ANY keyword in content (OR conditions)
    base =
      if keyword_patterns != [] do
        conditions = Enum.reduce(keyword_patterns, dynamic(false), fn pattern, acc ->
          dynamic([p], ^acc or ilike(p.content, ^pattern))
        end)
        where(base, ^conditions)
      else
        base
      end

    # Exclude keywords
    base =
      Enum.reduce(exclude, base, fn kw, q ->
        pattern = "%#{String.downcase(kw)}%"
        where(q, [p], not ilike(p.content, ^pattern))
      end)

    # Media only filter
    base = if excerpt.with_media_only, do: where(base, [p], p.post_type == "media"), else: base
    base = if max_id, do: where(base, [p], p.id < ^max_id), else: base

    base
    |> order_by([p], desc: p.published_at)
    |> limit(^limit)
    |> preload(:identity)
    |> Repo.all()
  end
end
