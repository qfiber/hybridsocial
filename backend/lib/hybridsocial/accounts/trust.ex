defmodule Hybridsocial.Accounts.Trust do
  @moduledoc """
  Computes and manages trust levels for identities.

  Trust levels:
    0 (new)         — account < 24h old
    1 (basic)       — account > 24h, has at least 1 post
    2 (established) — account > 7 days, 5+ posts, 2+ followers, no active warnings
    3 (trusted)     — account > 30 days, 20+ posts, 10+ followers, no warnings ever
  """

  import Ecto.Query
  alias Hybridsocial.Repo
  alias Hybridsocial.Accounts.Identity

  @doc "Compute trust level based on account age, activity, and moderation history."
  def compute_trust_level(identity) do
    identity = Repo.preload(identity, [], force: true)

    age_hours = age_in_hours(identity)
    post_count = count_posts(identity.id)
    follower_count = count_followers(identity.id)
    active_warnings = count_active_warnings(identity.id)
    total_warnings = count_total_warnings(identity.id)

    cond do
      age_hours >= 30 * 24 and post_count >= 20 and follower_count >= 10 and total_warnings == 0 ->
        3

      age_hours >= 7 * 24 and post_count >= 5 and follower_count >= 2 and active_warnings == 0 ->
        2

      age_hours >= 24 and post_count >= 1 ->
        1

      true ->
        0
    end
  end

  @doc "Recompute and persist the trust level on the identity."
  def refresh_trust_level(identity) do
    level = compute_trust_level(identity)

    identity
    |> Ecto.Changeset.change(trust_level: level)
    |> Repo.update()
  end

  @doc """
  Returns a map of restrictions for the given trust level.

  Keys:
    - :posts_per_day     — max posts allowed per day (nil = unlimited)
    - :dm_non_followers  — whether DMs to non-followers are allowed
    - :link_posting      — whether posting links is allowed
    - :auto_approve_reports — whether reports by this user are auto-approved
  """
  def trust_restrictions(trust_level) when is_integer(trust_level) do
    case trust_level do
      0 ->
        %{
          posts_per_day: 5,
          dm_non_followers: false,
          link_posting: false,
          auto_approve_reports: false
        }

      1 ->
        %{
          posts_per_day: 20,
          dm_non_followers: true,
          link_posting: true,
          auto_approve_reports: false
        }

      2 ->
        %{
          posts_per_day: 50,
          dm_non_followers: true,
          link_posting: true,
          auto_approve_reports: false
        }

      _ ->
        %{
          posts_per_day: nil,
          dm_non_followers: true,
          link_posting: true,
          auto_approve_reports: true
        }
    end
  end

  def trust_restrictions(%Identity{trust_level: level}), do: trust_restrictions(level || 0)

  # --- Private helpers ---

  defp age_in_hours(%{inserted_at: inserted_at}) do
    DateTime.diff(DateTime.utc_now(), inserted_at, :second) / 3600
  end

  defp count_posts(identity_id) do
    from(p in "posts",
      where: p.identity_id == ^identity_id and is_nil(p.deleted_at),
      select: count(p.id)
    )
    |> Repo.one() || 0
  end

  defp count_followers(identity_id) do
    from(f in "follows",
      where: f.target_id == ^identity_id,
      select: count(f.id)
    )
    |> Repo.one() || 0
  end

  defp count_active_warnings(identity_id) do
    from(w in "moderation_warnings",
      where: w.target_id == ^identity_id and w.acknowledged == false,
      select: count(w.id)
    )
    |> Repo.one() || 0
  rescue
    # Table may not exist yet
    _ -> 0
  end

  defp count_total_warnings(identity_id) do
    from(w in "moderation_warnings",
      where: w.target_id == ^identity_id,
      select: count(w.id)
    )
    |> Repo.one() || 0
  rescue
    _ -> 0
  end
end
