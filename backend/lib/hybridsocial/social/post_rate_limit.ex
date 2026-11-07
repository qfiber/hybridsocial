defmodule Hybridsocial.Social.PostRateLimit do
  @moduledoc """
  Limits how fast an account can create posts, per minute, hour and day.

  A limit resolves, for each window: the account's own override (set by staff in
  `identities.post_limits`), then a bot's own `posts_per_hour`, then the instance
  default (`user_posts_per_*` or `bot_posts_per_*`). `0` means unlimited, at any
  level, so staff can exempt one account or switch a default off.

  The count belongs to the person acting, so posting as a Page uses their own
  allowance. Counters only go up: deleting a post doesn't buy another one.

  Counting is an atomic Valkey increment, so parallel requests can't race past
  the limit. If Valkey is down this falls back to counting posts in the database:
  less exact, but a cache outage must not turn limits off.
  """
  import Ecto.Query

  alias Hybridsocial.Accounts.Bot
  alias Hybridsocial.Cache
  alias Hybridsocial.Config
  alias Hybridsocial.Repo
  alias Hybridsocial.Social.Post

  # Smallest first: an attempt refused by a short window doesn't use up the
  # longer ones, so hammering during a burst block doesn't burn the day's budget.
  @windows [minute: 60, hour: 3600, day: 86_400]

  @defaults %{
    user: %{minute: 6, hour: 20, day: 100},
    bot: %{minute: 10, hour: 30, day: 0}
  }

  @doc "The instance-wide defaults currently in force."
  def instance_defaults do
    Map.new(@defaults, fn {kind, limits} ->
      {kind, Map.new(limits, fn {window, _} -> {window, instance_default(kind, window)} end)}
    end)
  end

  @doc "The limits that apply to this account: `%{minute: n, hour: n, day: n}`."
  def limits_for(identity) do
    kind = if identity.is_bot, do: :bot, else: :user
    overrides = identity.post_limits || %{}

    Map.new(@windows, fn {window, _seconds} ->
      {window, override(overrides, window) || default_for(identity, kind, window)}
    end)
  end

  @doc """
  Records an attempt to post. `:ok`, or `{:error, %{window:, limit:, retry_after:}}`
  with `retry_after` in seconds. `counter` is replaceable for testing an outage.
  """
  def check(identity, counter \\ &Cache.increment/2) do
    if enabled?() do
      limits = limits_for(identity)

      Enum.reduce_while(@windows, :ok, fn {window, seconds}, :ok ->
        case check_window(identity, window, seconds, limits[window], counter) do
          :ok -> {:cont, :ok}
          {:error, _} = refused -> {:halt, refused}
        end
      end)
    else
      :ok
    end
  end

  defp enabled? do
    Application.get_env(:hybridsocial, :rate_limiting_enabled, true)
  end

  defp check_window(_identity, _window, _seconds, 0, _counter), do: :ok

  defp check_window(identity, window, seconds, limit, counter) do
    now = System.system_time(:second)
    key = "postrl:#{identity.id}:#{window}:#{div(now, seconds)}"

    over? =
      case counter.(key, seconds + 60) do
        {:ok, count} -> count > limit
        {:error, _} -> count_since(identity.id, seconds) >= limit
      end

    if over? do
      {:error, %{window: window, limit: limit, retry_after: max(seconds - rem(now, seconds), 1)}}
    else
      :ok
    end
  end

  # Includes deleted posts, matching the counters.
  defp count_since(identity_id, seconds) do
    since = DateTime.add(DateTime.utc_now(), -seconds, :second)

    Post
    |> where([p], p.identity_id == ^identity_id and p.inserted_at > ^since)
    |> Repo.aggregate(:count)
  end

  defp override(overrides, window) do
    case Map.get(overrides, "per_#{window}") do
      value when is_integer(value) and value >= 0 -> value
      _ -> nil
    end
  end

  defp default_for(%{id: id}, :bot, :hour) do
    case Repo.get(Bot, id) do
      %Bot{posts_per_hour: limit} when is_integer(limit) -> limit
      _ -> instance_default(:bot, :hour)
    end
  end

  defp default_for(_identity, kind, window), do: instance_default(kind, window)

  # Settings are stored untyped, so a stored string is possible. Anything
  # unusable falls back to the default rather than silently meaning unlimited.
  defp instance_default(kind, window) do
    default = @defaults[kind][window]

    case Config.get("#{kind}_posts_per_#{window}", default) do
      value when is_integer(value) and value >= 0 ->
        value

      value when is_binary(value) ->
        case Integer.parse(value) do
          {parsed, ""} when parsed >= 0 -> parsed
          _ -> default
        end

      _ ->
        default
    end
  end
end
