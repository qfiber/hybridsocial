defmodule Hybridsocial.Trending do
  @moduledoc """
  Trending context. Computes and retrieves trending posts, hashtags, and links.
  Uses precomputed data stored in the trending_data table.
  Supports OpenSearch aggregations when enabled, with PostgreSQL fallback.
  """
  import Ecto.Query

  alias Hybridsocial.Repo
  alias Hybridsocial.Search.TrendingData
  alias Hybridsocial.Social.{Post, Hashtag}
  alias Hybridsocial.Search.OpenSearch

  require Logger

  @default_limit 20
  @max_limit 40
  @half_life_hours 6
  @min_unique_accounts_posts 3
  @min_unique_accounts_hashtags 2

  @doc """
  Computes trending posts based on recent engagement velocity,
  account diversity, and time decay. Stores results in trending_data.
  """
  def compute_trending_posts do
    if search_backend() == "opensearch" do
      case opensearch_compute_trending_posts() do
        :ok -> :ok
        {:error, _reason} -> pg_compute_trending_posts()
      end
    else
      pg_compute_trending_posts()
    end
  end

  @doc """
  Computes trending hashtags based on usage in the last 24 hours.
  """
  def compute_trending_hashtags do
    if search_backend() == "opensearch" do
      case opensearch_compute_trending_hashtags() do
        :ok -> :ok
        {:error, _reason} -> pg_compute_trending_hashtags()
      end
    else
      pg_compute_trending_hashtags()
    end
  end

  @doc """
  Returns precomputed trending posts with limit/offset.
  """
  def get_trending_posts(opts \\ []) do
    limit = parse_limit(opts)
    offset = parse_offset(opts)

    trending =
      TrendingData
      |> where([t], t.type == "post")
      |> order_by([t], desc: t.score)
      |> limit(^limit)
      |> offset(^offset)
      |> Repo.all()

    post_ids = Enum.map(trending, & &1.target_id)

    posts =
      Post
      |> where([p], p.id in ^post_ids)
      |> where([p], is_nil(p.deleted_at))
      |> Repo.all()
      |> Repo.preload(:identity)
      |> Map.new(&{&1.id, &1})

    Enum.map(trending, fn td ->
      %{trending: td, post: Map.get(posts, td.target_id)}
    end)
    |> Enum.filter(fn %{post: post} -> post != nil end)
  end

  @doc """
  Returns precomputed trending hashtags with limit/offset.
  """
  def get_trending_hashtags(opts \\ []) do
    limit = parse_limit(opts)
    offset = parse_offset(opts)

    TrendingData
    |> where([t], t.type == "hashtag")
    |> order_by([t], desc: t.score)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc """
  Returns trending links. Placeholder for now.
  """
  def get_trending_links(_opts \\ []) do
    []
  end

  @doc """
  Removes trending_data older than 48 hours.
  """
  def cleanup_old_trending do
    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-48, :hour)
      |> DateTime.truncate(:microsecond)

    TrendingData
    |> where([t], t.computed_at < ^cutoff)
    |> Repo.delete_all()

    :ok
  end

  # --- OpenSearch Implementations ---

  defp opensearch_compute_trending_posts do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    cutoff = DateTime.add(now, -24, :hour)

    query = %{
      query: %{
        bool: %{
          filter: [
            %{term: %{visibility: "public"}},
            %{range: %{published_at: %{gte: DateTime.to_iso8601(cutoff)}}}
          ]
        }
      },
      aggs: %{
        top_posts: %{
          terms: %{field: "_id", size: 200},
          aggs: %{
            total_engagement: %{
              sum: %{
                script: %{
                  source:
                    "doc['reaction_count'].value + doc['boost_count'].value + doc['reply_count'].value"
                }
              }
            },
            published: %{
              max: %{field: "published_at"}
            }
          }
        }
      },
      size: 0
    }

    case OpenSearch.search("hybridsocial_posts", query, size: 0) do
      {:ok, %{aggregations: %{"top_posts" => %{"buckets" => buckets}}}} ->
        # Clear old trending posts
        TrendingData
        |> where([t], t.type == "post")
        |> Repo.delete_all()

        entries =
          buckets
          |> Enum.map(fn bucket ->
            post_id = bucket["key"]
            engagement = bucket["total_engagement"]["value"] || 0
            published_ms = bucket["published"]["value"] || 0
            published_dt = DateTime.from_unix!(trunc(published_ms / 1000))
            hours_old = DateTime.diff(now, published_dt, :second) / 3600.0
            decay = :math.pow(0.5, hours_old / @half_life_hours)
            score = engagement * decay

            %{post_id: post_id, score: score, engagement: engagement}
          end)
          |> Enum.filter(fn %{engagement: e} -> e >= @min_unique_accounts_posts end)
          |> Enum.sort_by(& &1.score, :desc)
          |> Enum.take(100)

        Enum.each(entries, fn %{post_id: post_id, score: score, engagement: eng} ->
          %TrendingData{}
          |> TrendingData.changeset(%{
            type: "post",
            target_id: post_id,
            score: score,
            computed_at: now,
            metadata: %{engagement: eng}
          })
          |> Repo.insert!()
        end)

        :ok

      {:error, reason} ->
        Logger.warning("OpenSearch trending posts aggregation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp opensearch_compute_trending_hashtags do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    cutoff = DateTime.add(now, -24, :hour)

    query = %{
      query: %{
        bool: %{
          filter: [
            %{range: %{inserted_at: %{gte: DateTime.to_iso8601(cutoff)}}}
          ]
        }
      },
      aggs: %{
        trending_hashtags: %{
          terms: %{field: "hashtags", size: 100}
        }
      },
      size: 0
    }

    case OpenSearch.search("hybridsocial_posts", query, size: 0) do
      {:ok, %{aggregations: %{"trending_hashtags" => %{"buckets" => buckets}}}} ->
        # Clear old trending hashtags
        TrendingData
        |> where([t], t.type == "hashtag")
        |> Repo.delete_all()

        buckets
        |> Enum.filter(fn bucket -> bucket["doc_count"] >= @min_unique_accounts_hashtags end)
        |> Enum.each(fn bucket ->
          name = bucket["key"]
          post_count = bucket["doc_count"]
          score = post_count * :math.log(post_count + 1)

          %TrendingData{}
          |> TrendingData.changeset(%{
            type: "hashtag",
            target_id: name,
            score: score,
            computed_at: now,
            metadata: %{post_count: post_count}
          })
          |> Repo.insert!()
        end)

        :ok

      {:error, reason} ->
        Logger.warning("OpenSearch trending hashtags aggregation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # --- PostgreSQL Implementations (fallback) ---

  defp pg_compute_trending_posts do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    cutoff = DateTime.add(now, -24, :hour)

    results =
      Post
      |> where([p], is_nil(p.deleted_at))
      |> where([p], p.visibility == "public")
      |> where([p], p.published_at >= ^cutoff)
      |> join(:left, [p], r in "reactions", on: r.post_id == p.id and r.inserted_at >= ^cutoff)
      |> join(:left, [p, _r], b in "boosts",
        on: b.post_id == p.id and b.inserted_at >= ^cutoff and is_nil(b.deleted_at)
      )
      |> join(:left, [p, _r, _b], rep in "posts",
        on: rep.parent_id == p.id and rep.inserted_at >= ^cutoff and is_nil(rep.deleted_at)
      )
      |> group_by([p, _r, _b, _rep], p.id)
      |> select([p, r, b, rep], %{
        post_id: p.id,
        published_at: p.published_at,
        reaction_count: count(r.id, :distinct),
        boost_count: count(b.id, :distinct),
        reply_count: count(rep.id, :distinct),
        unique_reactors: fragment("COUNT(DISTINCT ?)", r.identity_id),
        unique_boosters: fragment("COUNT(DISTINCT ?)", b.identity_id),
        unique_repliers: fragment("COUNT(DISTINCT ?)", rep.identity_id)
      })
      |> Repo.all()

    # Clear old trending posts
    TrendingData
    |> where([t], t.type == "post")
    |> Repo.delete_all()

    # Compute scores and insert
    trending_entries =
      results
      |> Enum.map(fn row ->
        approx_unique = row.unique_reactors + row.unique_boosters + row.unique_repliers

        total_engagement = row.reaction_count + row.boost_count + row.reply_count
        hours_old = DateTime.diff(now, row.published_at, :second) / 3600.0
        decay = :math.pow(0.5, hours_old / @half_life_hours)
        score = total_engagement * decay * :math.log(max(approx_unique, 1) + 1)

        %{
          row: row,
          score: score,
          approx_unique: approx_unique,
          total_engagement: total_engagement
        }
      end)
      |> Enum.filter(fn %{approx_unique: u} -> u >= @min_unique_accounts_posts end)
      |> Enum.sort_by(& &1.score, :desc)
      |> Enum.take(100)

    Enum.each(trending_entries, fn %{
                                     row: row,
                                     score: score,
                                     total_engagement: eng,
                                     approx_unique: uniq
                                   } ->
      %TrendingData{}
      |> TrendingData.changeset(%{
        type: "post",
        target_id: row.post_id,
        score: score,
        computed_at: now,
        metadata: %{
          engagement: eng,
          unique_accounts: uniq
        }
      })
      |> Repo.insert!()
    end)

    :ok
  end

  defp pg_compute_trending_hashtags do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    cutoff = DateTime.add(now, -24, :hour)

    results =
      Hashtag
      |> join(:inner, [h], ph in "post_hashtags", on: ph.hashtag_id == h.id)
      |> join(:inner, [_h, ph], p in Post,
        on: p.id == ph.post_id and p.inserted_at >= ^cutoff and is_nil(p.deleted_at)
      )
      |> group_by([h, _ph, _p], [h.id, h.name])
      |> select([h, _ph, p], %{
        hashtag_id: h.id,
        name: h.name,
        post_count: count(p.id, :distinct),
        unique_accounts: fragment("COUNT(DISTINCT ?)", p.identity_id)
      })
      |> having(
        [_h, _ph, p],
        fragment("COUNT(DISTINCT ?)", p.identity_id) >= ^@min_unique_accounts_hashtags
      )
      |> Repo.all()

    # Clear old trending hashtags
    TrendingData
    |> where([t], t.type == "hashtag")
    |> Repo.delete_all()

    # Compute scores and insert
    results
    |> Enum.each(fn row ->
      score = row.post_count * :math.log(row.unique_accounts + 1)

      %TrendingData{}
      |> TrendingData.changeset(%{
        type: "hashtag",
        target_id: row.name,
        score: score,
        computed_at: now,
        metadata: %{
          post_count: row.post_count,
          unique_accounts: row.unique_accounts
        }
      })
      |> Repo.insert!()
    end)

    :ok
  end

  defp search_backend do
    Hybridsocial.Search.search_backend()
  end

  defp parse_limit(opts) do
    opts
    |> Keyword.get(:limit, @default_limit)
    |> min(@max_limit)
    |> max(1)
  end

  defp parse_offset(opts) do
    opts
    |> Keyword.get(:offset, 0)
    |> max(0)
  end
end
