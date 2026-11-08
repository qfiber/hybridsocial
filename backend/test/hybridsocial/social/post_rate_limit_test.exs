defmodule Hybridsocial.Social.PostRateLimitTest do
  use Hybridsocial.DataCase, async: false

  alias Hybridsocial.Accounts.{Bot, Identity}
  alias Hybridsocial.Config
  alias Hybridsocial.Social.{PostRateLimit, Posts}

  setup do
    Application.put_env(:hybridsocial, :rate_limiting_enabled, true)
    on_exit(fn -> Application.put_env(:hybridsocial, :rate_limiting_enabled, false) end)

    Ecto.Adapters.SQL.Sandbox.mode(Hybridsocial.Repo, {:shared, self()})
    start_supervised!(Hybridsocial.Config.Store)
    :ok
  end

  defp user(limits \\ %{}) do
    identity = create_user("rl#{System.unique_integer([:positive])}")
    identity |> Ecto.Changeset.change(post_limits: limits) |> Repo.update!()
  end

  defp attempts(identity, count) do
    for _ <- 1..count, do: PostRateLimit.check(identity)
  end

  describe "limits_for/1" do
    test "a user gets the built-in defaults, with limits on by default" do
      assert PostRateLimit.limits_for(user()) == %{minute: 6, hour: 20, day: 100}
    end

    test "an instance setting replaces a default, even stored as a string" do
      :ok = Config.set("user_posts_per_hour", 7)
      :ok = Config.set("user_posts_per_day", "9")

      assert %{minute: 6, hour: 7, day: 9} = PostRateLimit.limits_for(user())
    end

    test "an unusable setting falls back to the default rather than meaning unlimited" do
      :ok = Config.set("user_posts_per_hour", "lots")

      assert %{hour: 20} = PostRateLimit.limits_for(user())
    end

    test "an account override beats the instance setting, window by window" do
      :ok = Config.set("user_posts_per_hour", 7)

      assert PostRateLimit.limits_for(user(%{"per_day" => 3})) == %{minute: 6, hour: 7, day: 3}
    end

    test "a bot's own hourly limit applies, under any account override" do
      identity = user()

      bot =
        identity
        |> Ecto.Changeset.change(is_bot: true)
        |> Repo.update!()

      assert %{minute: 10, hour: 30, day: 0} = PostRateLimit.limits_for(bot)

      Repo.insert!(%Bot{identity_id: bot.id, posts_per_hour: 5})
      assert %{hour: 5} = PostRateLimit.limits_for(bot)

      bot = bot |> Ecto.Changeset.change(post_limits: %{"per_hour" => 2}) |> Repo.update!()
      assert %{hour: 2} = PostRateLimit.limits_for(bot)
    end
  end

  describe "check/2" do
    test "refuses past the limit and says which window, the limit and when to retry" do
      identity = user(%{"per_minute" => 2})

      assert [:ok, :ok] = attempts(identity, 2)

      assert {:error, %{window: :minute, limit: 2, retry_after: retry_after}} =
               PostRateLimit.check(identity)

      assert retry_after in 1..60
    end

    test "each window is enforced" do
      identity = user(%{"per_minute" => 0, "per_hour" => 1})
      assert :ok = PostRateLimit.check(identity)
      assert {:error, %{window: :hour}} = PostRateLimit.check(identity)

      identity = user(%{"per_minute" => 0, "per_hour" => 0, "per_day" => 1})
      assert :ok = PostRateLimit.check(identity)
      assert {:error, %{window: :day}} = PostRateLimit.check(identity)
    end

    test "0 means unlimited" do
      identity = user(%{"per_minute" => 0, "per_hour" => 0, "per_day" => 0})
      assert Enum.all?(attempts(identity, 150), &(&1 == :ok))
    end

    test "attempts refused by a short window don't use up the longer ones" do
      identity = user(%{"per_minute" => 1, "per_hour" => 2})

      assert :ok = PostRateLimit.check(identity)
      for _ <- 1..5, do: assert({:error, %{window: :minute}} = PostRateLimit.check(identity))

      hour_key =
        "postrl:#{identity.id}:hour:#{div(System.system_time(:second), 3600)}"

      assert Hybridsocial.Cache.get(hour_key) == 1
    end

    test "parallel requests can't race past the limit" do
      identity = user(%{"per_minute" => 5})

      results =
        1..40
        |> Task.async_stream(fn _ -> PostRateLimit.check(identity) end, max_concurrency: 40)
        |> Enum.map(fn {:ok, result} -> result end)

      assert Enum.count(results, &(&1 == :ok)) == 5
    end

    test "with Valkey down it counts posts in the database instead of letting all through" do
      identity = user(%{"per_minute" => 2})
      down = fn _key, _ttl -> {:error, :unavailable} end

      assert :ok = PostRateLimit.check(identity, down)

      {:ok, first} = Posts.create_post(identity.id, %{"content" => "one"})
      {:ok, _} = Posts.create_post(identity.id, %{"content" => "two"})

      assert {:error, %{window: :minute}} = PostRateLimit.check(identity, down)

      # A deleted post still counts, as it does with the counters.
      {:ok, _} = Posts.delete_post(first.id, identity.id)
      assert {:error, %{window: :minute}} = PostRateLimit.check(identity, down)
    end

    test "with Valkey down the database count ignores replies" do
      identity = user(%{"per_minute" => 2})
      down = fn _key, _ttl -> {:error, :unavailable} end

      {:ok, parent} = Posts.create_post(identity.id, %{"content" => "one"})

      for n <- 1..3,
          do:
            {:ok, _} =
              Posts.create_post(identity.id, %{"content" => "r#{n}", "parent_id" => parent.id})

      assert :ok = PostRateLimit.check(identity, down)
    end

    test "check_post/2 lets replies through without counting them" do
      identity = user(%{"per_minute" => 1})
      assert :ok = PostRateLimit.check_post(identity, %{"content" => "post"})

      for _ <- 1..3,
          do:
            assert(
              :ok = PostRateLimit.check_post(identity, %{"parent_id" => Ecto.UUID.generate()})
            )

      assert {:error, %{window: :minute}} = PostRateLimit.check_post(identity, %{})
    end

    test "does nothing when rate limiting is disabled" do
      Application.put_env(:hybridsocial, :rate_limiting_enabled, false)
      identity = user(%{"per_minute" => 1})

      assert [:ok, :ok, :ok] = attempts(identity, 3)
    end
  end

  test "an identity's post_limits can't be set through any user-facing changeset" do
    identity = user()

    changeset = Identity.update_changeset(identity, %{"post_limits" => %{"per_day" => 0}})

    refute Map.has_key?(changeset.changes, :post_limits)
  end
end
