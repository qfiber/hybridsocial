defmodule Hybridsocial.Feeds.Algorithms.TrendingTest do
  use ExUnit.Case, async: true

  alias Hybridsocial.Feeds.Algorithms.Trending
  alias Hybridsocial.Social.Post

  describe "score_post/2 — engagement dominates recency" do
    setup do
      %{now: ~U[2026-01-02 00:00:00.000000Z]}
    end

    test "an older well-engaged post outranks a fresh, barely-engaged burst", %{now: now} do
      ctx = %{now: now, follower_counts: %{}}

      # 15h old, real engagement (5 reactions + 3 replies).
      engaged_older = %Post{
        identity_id: "a",
        reaction_count: 5,
        boost_count: 0,
        reply_count: 3,
        inserted_at: DateTime.add(now, -15 * 3600, :second)
      }

      # 30 min old, a small burst (3 reactions). Under the old ~6h half-life
      # this beat the engaged post; it must no longer.
      fresh_burst = %Post{
        identity_id: "b",
        reaction_count: 3,
        boost_count: 0,
        reply_count: 0,
        inserted_at: DateTime.add(now, -30 * 60, :second)
      }

      assert Trending.score_post(engaged_older, ctx) > Trending.score_post(fresh_burst, ctx)
    end

    test "with equal age, more engagement scores higher", %{now: now} do
      ctx = %{now: now, follower_counts: %{}}
      at = DateTime.add(now, -3 * 3600, :second)

      more = %Post{
        identity_id: "a",
        reaction_count: 20,
        boost_count: 2,
        reply_count: 4,
        inserted_at: at
      }

      less = %Post{
        identity_id: "b",
        reaction_count: 2,
        boost_count: 0,
        reply_count: 0,
        inserted_at: at
      }

      assert Trending.score_post(more, ctx) > Trending.score_post(less, ctx)
    end
  end
end
