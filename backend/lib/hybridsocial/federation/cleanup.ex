defmodule Hybridsocial.Federation.Cleanup do
  @moduledoc """
  Handles content purging when an instance is defederated (suspended).

  When an admin suspends an instance, all content from remote identities on that
  domain should be soft-deleted. This module provides the purge and restore logic.
  """

  import Ecto.Query

  alias Hybridsocial.Repo
  alias Hybridsocial.Accounts.Identity
  alias Hybridsocial.Social.{Post, Follow, Reaction, Boost}

  require Logger

  @doc """
  Purges all content from identities belonging to the given domain.

  Soft-deletes posts, removes follows, reactions, and boosts from/to identities
  on that domain. All deletions use a shared timestamp so they can be restored.

  ## Options

    - `:dry_run` — when `true`, returns stats without modifying data (default: `false`)

  Returns `{:ok, stats}` where stats is a map with counts of affected records.
  """
  def purge_instance_content(domain, opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, false)
    domain = String.downcase(domain)
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    # Find all remote identities from this domain
    identity_ids = get_domain_identity_ids(domain)

    if dry_run do
      stats = compute_purge_stats(identity_ids)
      {:ok, Map.put(stats, :dry_run, true)}
    else
      stats = execute_purge(identity_ids, now)
      Logger.info("Purged content from #{domain}: #{inspect(stats)}")
      {:ok, Map.put(stats, :dry_run, false)}
    end
  end

  @doc """
  Restores content that was purged from a domain at a specific timestamp.

  Un-deletes posts and boosts where `deleted_at` matches the purge timestamp.
  Follows, reactions, and boosts without soft-delete are hard-deleted during purge
  and cannot be restored, but posts and boosts with `deleted_at` can be.

  If no `purge_timestamp` is provided, restores all soft-deleted content from the
  domain's identities (useful when the exact timestamp is unknown).
  """
  def restore_instance_content(domain, opts \\ []) do
    domain = String.downcase(domain)
    purge_timestamp = Keyword.get(opts, :purge_timestamp)

    identity_ids = get_domain_identity_ids(domain)

    if identity_ids == [] do
      {:ok, %{posts_restored: 0, boosts_restored: 0}}
    else
      stats = execute_restore(identity_ids, purge_timestamp)
      Logger.info("Restored content from #{domain}: #{inspect(stats)}")
      {:ok, stats}
    end
  end

  # --- Private ---

  defp get_domain_identity_ids(domain) do
    # Remote identities have ap_actor_url containing the domain
    # e.g., "https://example.com/users/alice"
    like_pattern = "%://#{domain}/%"

    Identity
    |> where([i], like(i.ap_actor_url, ^like_pattern))
    |> where([i], is_nil(i.deleted_at))
    |> select([i], i.id)
    |> Repo.all()
  end

  defp compute_purge_stats(identity_ids) when identity_ids == [] do
    %{
      identities_affected: 0,
      posts_removed: 0,
      follows_removed: 0,
      reactions_removed: 0,
      boosts_removed: 0
    }
  end

  defp compute_purge_stats(identity_ids) do
    posts_count =
      Post
      |> where([p], p.identity_id in ^identity_ids and is_nil(p.deleted_at))
      |> Repo.aggregate(:count)

    follows_count =
      Follow
      |> where(
        [f],
        f.follower_id in ^identity_ids or f.followee_id in ^identity_ids
      )
      |> Repo.aggregate(:count)

    reactions_count =
      Reaction
      |> where([r], r.identity_id in ^identity_ids)
      |> Repo.aggregate(:count)

    boosts_count =
      Boost
      |> where([b], b.identity_id in ^identity_ids and is_nil(b.deleted_at))
      |> Repo.aggregate(:count)

    %{
      identities_affected: length(identity_ids),
      posts_removed: posts_count,
      follows_removed: follows_count,
      reactions_removed: reactions_count,
      boosts_removed: boosts_count
    }
  end

  defp execute_purge(identity_ids, _now) when identity_ids == [] do
    %{
      identities_affected: 0,
      posts_removed: 0,
      follows_removed: 0,
      reactions_removed: 0,
      boosts_removed: 0
    }
  end

  defp execute_purge(identity_ids, now) do
    # Soft-delete all posts from those identities
    {posts_removed, _} =
      Post
      |> where([p], p.identity_id in ^identity_ids and is_nil(p.deleted_at))
      |> Repo.update_all(set: [deleted_at: now])

    # Hard-delete follows to/from those identities
    {follows_removed, _} =
      Follow
      |> where(
        [f],
        f.follower_id in ^identity_ids or f.followee_id in ^identity_ids
      )
      |> Repo.delete_all()

    # Hard-delete reactions from those identities
    {reactions_removed, _} =
      Reaction
      |> where([r], r.identity_id in ^identity_ids)
      |> Repo.delete_all()

    # Soft-delete boosts from those identities
    {boosts_removed, _} =
      Boost
      |> where([b], b.identity_id in ^identity_ids and is_nil(b.deleted_at))
      |> Repo.update_all(set: [deleted_at: now])

    %{
      identities_affected: length(identity_ids),
      posts_removed: posts_removed,
      follows_removed: follows_removed,
      reactions_removed: reactions_removed,
      boosts_removed: boosts_removed
    }
  end

  defp execute_restore(identity_ids, nil) do
    # Restore all soft-deleted posts from domain identities
    {posts_restored, _} =
      Post
      |> where([p], p.identity_id in ^identity_ids and not is_nil(p.deleted_at))
      |> Repo.update_all(set: [deleted_at: nil])

    {boosts_restored, _} =
      Boost
      |> where([b], b.identity_id in ^identity_ids and not is_nil(b.deleted_at))
      |> Repo.update_all(set: [deleted_at: nil])

    %{posts_restored: posts_restored, boosts_restored: boosts_restored}
  end

  defp execute_restore(identity_ids, purge_timestamp) do
    # Restore only content deleted at the exact purge timestamp
    {posts_restored, _} =
      Post
      |> where([p], p.identity_id in ^identity_ids and p.deleted_at == ^purge_timestamp)
      |> Repo.update_all(set: [deleted_at: nil])

    {boosts_restored, _} =
      Boost
      |> where([b], b.identity_id in ^identity_ids and b.deleted_at == ^purge_timestamp)
      |> Repo.update_all(set: [deleted_at: nil])

    %{posts_restored: posts_restored, boosts_restored: boosts_restored}
  end
end
