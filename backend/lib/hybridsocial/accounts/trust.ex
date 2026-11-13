defmodule Hybridsocial.Accounts.Trust do
  @moduledoc """
  Trust levels for local accounts, and the new-account gates they drive (#67).

  Levels, computed from account age, post count and accepted followers:

    * 0 (new)         - under the level 1 thresholds
    * 1 (basic)       - `trust_level_1_hours` old with `trust_level_1_posts` posts
    * 2 (established) - `trust_level_2_*` age, posts and followers
    * 3 (trusted)     - `trust_level_3_*` age, posts and followers
    * 4 (vouched)     - staff only; never computed

  Every threshold is an admin setting (defaults: 24h/1 post, 7d/5 posts/2
  followers, 30d/20 posts/10 followers).

  A level staff set by hand is pinned (`trust_level_locked`) and the
  recompute leaves it alone; staff can hand it back to the computation.

  ## Gates

  A level 0 account can't post links (`trust_gate_links`) or start a DM with
  someone who doesn't follow it (`trust_gate_dms`). Both settings default on.
  Level 1 lifts both, so a real user is clear after a day and a first post.
  The gates never apply to staff, to an account on a paid tier, or to remote
  accounts. A subaccount (page, bot, group) is judged by its owner.

  The level is recomputed by `Accounts.TrustLevelWorker` on a sweep, and
  on the spot when a level 0 account hits a gate, so nobody waits for the
  sweep to be let through.
  """

  import Ecto.Query

  alias Hybridsocial.Accounts.Identity
  alias Hybridsocial.Auth.RBAC
  alias Hybridsocial.Config
  alias Hybridsocial.Premium.TierLimits
  alias Hybridsocial.Repo
  alias Hybridsocial.Social.Follow

  @max_computed_level 3
  @max_level 4

  @thresholds %{
    1 => %{hours: 24, posts: 1, followers: 0},
    2 => %{hours: 168, posts: 5, followers: 2},
    3 => %{hours: 720, posts: 20, followers: 10}
  }

  # Anything a browser would follow: a scheme, or a bare `www.` host.
  @link_regex ~r{https?://|\bwww\.[a-z0-9-]+\.[a-z]}i

  @doc "The highest level staff can set."
  def max_level, do: @max_level

  @doc "The highest level the computation produces; above it is staff-only."
  def max_computed_level, do: @max_computed_level

  @doc "The thresholds in force, per level: `%{1 => %{hours:, posts:, followers:}, ...}`."
  def thresholds do
    Map.new(@thresholds, fn {level, defaults} ->
      {level,
       Map.new(defaults, fn {key, default} ->
         {key, config_int("trust_level_#{level}_#{key}", default)}
       end)}
    end)
  end

  @doc "Compute the level an identity has earned (0..3)."
  def compute_trust_level(%Identity{} = identity) do
    age_hours = DateTime.diff(DateTime.utc_now(), identity.inserted_at, :second) / 3600
    posts = count_posts(identity.id)
    followers = count_followers(identity.id)
    thresholds = thresholds()

    @max_computed_level..1//-1
    |> Enum.find(0, fn level ->
      %{hours: hours, posts: min_posts, followers: min_followers} = thresholds[level]
      age_hours >= hours and posts >= min_posts and followers >= min_followers
    end)
  end

  @doc """
  Recompute and persist the level. A pinned level is returned unchanged, and
  nothing is written when the level hasn't moved.
  """
  def refresh_trust_level(%Identity{trust_level_locked: true} = identity), do: {:ok, identity}

  def refresh_trust_level(%Identity{} = identity) do
    case compute_trust_level(identity) do
      level when level == identity.trust_level ->
        {:ok, identity}

      level ->
        identity
        |> Ecto.Changeset.change(trust_level: level)
        |> Repo.update()
    end
  end

  @doc """
  What the account may do right now, as the client sees it in `/me`.
  Reads the stored level; doesn't recompute.
  """
  def trust_restrictions(%Identity{} = identity) do
    restricted = gated?(identity, refresh: false)

    %{
      link_posting: not (restricted and gate_enabled?("trust_gate_links")),
      dm_non_followers: not (restricted and gate_enabled?("trust_gate_dms"))
    }
  end

  @doc """
  `:ok`, or `{:error, :trust_links_not_allowed}` when a gated account's text
  contains a link. `texts` is every user-written field of the post.
  """
  def check_links(identity, texts) do
    if gate_enabled?("trust_gate_links") and contains_link?(texts) and gated?(identity) do
      {:error, :trust_links_not_allowed}
    else
      :ok
    end
  end

  @doc """
  `:ok`, or `{:error, :trust_dm_not_allowed}` when a gated account tries to
  reach anyone in `recipient_ids` who doesn't follow it.
  """
  def check_dm(_sender, []), do: :ok

  def check_dm(sender, recipient_ids) do
    sender_id = sender && sender.id

    if gate_enabled?("trust_gate_dms") and
         Enum.any?(recipient_ids, &(&1 != sender_id and not follows?(&1, sender_id))) and
         gated?(sender) do
      {:error, :trust_dm_not_allowed}
    else
      :ok
    end
  end

  @doc "Whether any of `texts` contains a link."
  def contains_link?(texts) do
    texts
    |> List.wrap()
    |> List.flatten()
    |> Enum.any?(&(is_binary(&1) and Regex.match?(@link_regex, &1)))
  end

  # --- Gate subject ---

  # Whether the new-account gates apply. Cheapest checks first: most callers
  # are already past level 0 and never touch the database.
  defp gated?(identity, opts \\ [])
  defp gated?(nil, _opts), do: false

  defp gated?(%Identity{parent_identity_id: parent_id}, opts) when is_binary(parent_id) do
    case Repo.get(Identity, parent_id) do
      # A subaccount whose owner is gone is judged on its own.
      nil -> false
      parent -> gated?(parent, opts)
    end
  end

  defp gated?(%Identity{} = identity, opts) do
    cond do
      identity.is_local == false -> false
      (identity.trust_level || 0) >= 1 -> false
      paid_tier?(identity) -> false
      RBAC.staff?(identity.id) -> false
      identity.trust_level_locked -> true
      Keyword.get(opts, :refresh, true) -> still_new_after_refresh?(identity)
      true -> true
    end
  end

  defp still_new_after_refresh?(identity) do
    case refresh_trust_level(identity) do
      {:ok, %Identity{trust_level: level}} -> level < 1
      _ -> true
    end
  end

  # Only a tier someone chose counts. With tiers off, `TierLimits` hands
  # everyone Pro limits, which says nothing about the account.
  defp paid_tier?(identity) do
    TierLimits.enabled?() and identity.verification_tier not in [nil, "free"]
  end

  defp follows?(follower_id, target_id) do
    Follow
    |> where(
      [f],
      f.follower_id == ^follower_id and f.followee_id == ^target_id and f.status == :accepted
    )
    |> Repo.exists?()
  end

  # --- Counts ---

  defp count_posts(identity_id) do
    from(p in "posts",
      where: p.identity_id == type(^identity_id, Ecto.UUID) and is_nil(p.deleted_at),
      select: count(p.id)
    )
    |> Repo.one() || 0
  end

  defp count_followers(identity_id) do
    Follow
    |> where([f], f.followee_id == ^identity_id and f.status == :accepted)
    |> Repo.aggregate(:count)
  end

  # --- Config ---

  defp gate_enabled?(key), do: Config.get(key, true) not in [false, "false"]

  defp config_int(key, default) do
    case Config.get(key, default) do
      n when is_integer(n) and n >= 0 ->
        n

      n when is_binary(n) ->
        case Integer.parse(n) do
          {int, ""} when int >= 0 -> int
          _ -> default
        end

      _ ->
        default
    end
  end
end
