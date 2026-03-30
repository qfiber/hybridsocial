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

  @doc "Fetch posts matching an excerpt's keyword filters. Uses OpenSearch when available, PostgreSQL as fallback."
  def excerpt_feed(excerpt, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    max_id = Keyword.get(opts, :max_id)

    case excerpt_feed_opensearch(excerpt, limit, max_id) do
      {:ok, posts} when posts != [] -> posts
      _ -> excerpt_feed_postgresql(excerpt, limit, max_id)
    end
  end

  # --- OpenSearch path (fast, inverted index) ---

  defp excerpt_feed_opensearch(excerpt, limit, max_id) do
    alias Hybridsocial.Search.OpenSearch

    keywords = excerpt.keywords || []
    exclude = excerpt.exclude_keywords || []

    if keywords == [] do
      {:ok, []}
    else
      # Build a bool query: should (any keyword), must_not (exclude keywords)
      should_clauses = Enum.map(keywords, fn kw ->
        %{match: %{content: %{query: kw, operator: "and"}}}
      end)

      must_not_clauses = Enum.map(exclude, fn kw ->
        %{match: %{content: %{query: kw, operator: "and"}}}
      end)

      filter_clauses = [
        %{term: %{visibility: "public"}}
      ]

      filter_clauses =
        if excerpt.with_media_only do
          [%{term: %{post_type: "media"}} | filter_clauses]
        else
          filter_clauses
        end

      query = %{
        query: %{
          bool: %{
            should: should_clauses,
            minimum_should_match: 1,
            must_not: must_not_clauses,
            filter: filter_clauses
          }
        },
        sort: [%{published_at: %{order: "desc"}}],
        size: limit
      }

      # Add search_after for pagination if max_id provided
      query =
        if max_id do
          Map.put(query, :search_after, [max_id])
        else
          query
        end

      case OpenSearch.search("hybridsocial_posts", query) do
        {:ok, %{"hits" => %{"hits" => hits}}} ->
          post_ids = Enum.map(hits, fn hit -> hit["_id"] end)

          if post_ids == [] do
            {:ok, []}
          else
            posts =
              Post
              |> where([p], p.id in ^post_ids and is_nil(p.deleted_at))
              |> preload(:identity)
              |> Repo.all()

            # Maintain OpenSearch ordering
            id_order = Enum.with_index(post_ids) |> Map.new()
            sorted = Enum.sort_by(posts, fn p -> Map.get(id_order, p.id, 999) end)
            {:ok, sorted}
          end

        _ ->
          {:error, :opensearch_failed}
      end
    end
  rescue
    _ -> {:error, :opensearch_failed}
  end

  # --- PostgreSQL fallback (slower but always works) ---

  defp excerpt_feed_postgresql(excerpt, limit, max_id) do
    keywords = excerpt.keywords || []
    exclude = excerpt.exclude_keywords || []
    keyword_patterns = Enum.map(keywords, fn kw -> "%#{String.downcase(kw)}%" end)

    base =
      Post
      |> where([p], is_nil(p.deleted_at))
      |> where([p], p.visibility == "public")
      |> where([p], is_nil(p.parent_id))

    base =
      if keyword_patterns != [] do
        conditions = Enum.reduce(keyword_patterns, dynamic(false), fn pattern, acc ->
          dynamic([p], ^acc or ilike(p.content, ^pattern))
        end)
        where(base, ^conditions)
      else
        base
      end

    base =
      Enum.reduce(exclude, base, fn kw, q ->
        pattern = "%#{String.downcase(kw)}%"
        where(q, [p], not ilike(p.content, ^pattern))
      end)

    base = if excerpt.with_media_only, do: where(base, [p], p.post_type == "media"), else: base
    base = if max_id, do: where(base, [p], p.id < ^max_id), else: base

    base
    |> order_by([p], desc: p.published_at)
    |> limit(^limit)
    |> preload(:identity)
    |> Repo.all()
  end
end
