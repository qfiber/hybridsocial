defmodule Hybridsocial.Social do
  @moduledoc """
  The Social context. Manages follows, blocks, and mutes between identities.
  """
  import Ecto.Query

  alias Hybridsocial.Repo
  alias Hybridsocial.Accounts
  alias Hybridsocial.Social.{Follow, Block, Mute}

  # --- Follows ---

  def follow(follower_id, followee_id) do
    with {:not_self, true} <- {:not_self, follower_id != followee_id},
         {:not_blocked, false} <- {:not_blocked, blocked?(followee_id, follower_id)},
         target when not is_nil(target) <- Accounts.get_identity(followee_id) do
      status = if target.is_locked, do: :pending, else: :accepted

      %Follow{}
      |> Follow.changeset(%{
        follower_id: follower_id,
        followee_id: followee_id,
        status: status
      })
      |> Repo.insert(
        on_conflict: {:replace, [:status, :updated_at]},
        conflict_target: [:follower_id, :followee_id],
        returning: true
      )
    else
      {:not_self, false} -> {:error, :cannot_follow_self}
      {:not_blocked, true} -> {:error, :blocked}
      nil -> {:error, :not_found}
    end
  end

  def unfollow(follower_id, followee_id) do
    Follow
    |> where([f], f.follower_id == ^follower_id and f.followee_id == ^followee_id)
    |> Repo.delete_all()

    :ok
  end

  def accept_follow(follow_id) do
    case Repo.get(Follow, follow_id) do
      nil -> {:error, :not_found}
      follow -> follow |> Follow.status_changeset(:accepted) |> Repo.update()
    end
  end

  def reject_follow(follow_id) do
    case Repo.get(Follow, follow_id) do
      nil -> {:error, :not_found}
      follow -> follow |> Follow.status_changeset(:rejected) |> Repo.update()
    end
  end

  def following?(follower_id, followee_id) do
    Follow
    |> where(
      [f],
      f.follower_id == ^follower_id and
        f.followee_id == ^followee_id and
        f.status == :accepted
    )
    |> Repo.exists?()
  end

  def followers(identity_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 40)
    offset = Keyword.get(opts, :offset, 0)

    Follow
    |> where([f], f.followee_id == ^identity_id and f.status == :accepted)
    |> join(:inner, [f], i in assoc(f, :follower))
    |> select([f, i], i)
    |> order_by([f], desc: f.inserted_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  def following(identity_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 40)
    offset = Keyword.get(opts, :offset, 0)

    Follow
    |> where([f], f.follower_id == ^identity_id and f.status == :accepted)
    |> join(:inner, [f], i in assoc(f, :followee))
    |> select([f, i], i)
    |> order_by([f], desc: f.inserted_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  def followers_count(identity_id) do
    Follow
    |> where([f], f.followee_id == ^identity_id and f.status == :accepted)
    |> Repo.aggregate(:count)
  end

  def following_count(identity_id) do
    Follow
    |> where([f], f.follower_id == ^identity_id and f.status == :accepted)
    |> Repo.aggregate(:count)
  end

  # --- Blocks ---

  def block(blocker_id, blocked_id) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:remove_follows, fn repo, _changes ->
      {count, _} =
        Follow
        |> where(
          [f],
          (f.follower_id == ^blocker_id and f.followee_id == ^blocked_id) or
            (f.follower_id == ^blocked_id and f.followee_id == ^blocker_id)
        )
        |> repo.delete_all()

      {:ok, count}
    end)
    |> Ecto.Multi.run(:block, fn repo, _changes ->
      changeset = Block.changeset(%Block{}, %{blocker_id: blocker_id, blocked_id: blocked_id})

      case repo.insert(changeset,
             on_conflict: :nothing,
             conflict_target: [:blocker_id, :blocked_id]
           ) do
        {:ok, block} ->
          # on_conflict: :nothing may return a struct with nil id; fetch existing if so
          if block.id do
            {:ok, block}
          else
            existing =
              Block
              |> where([b], b.blocker_id == ^blocker_id and b.blocked_id == ^blocked_id)
              |> repo.one()

            {:ok, existing}
          end

        {:error, changeset} ->
          {:error, changeset}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{block: block}} -> {:ok, block}
      {:error, :block, changeset, _} -> {:error, changeset}
    end
  end

  def unblock(blocker_id, blocked_id) do
    Block
    |> where([b], b.blocker_id == ^blocker_id and b.blocked_id == ^blocked_id)
    |> Repo.delete_all()

    :ok
  end

  def blocked?(blocker_id, blocked_id) do
    Block
    |> where([b], b.blocker_id == ^blocker_id and b.blocked_id == ^blocked_id)
    |> Repo.exists?()
  end

  def blocking_ids(identity_id) do
    Block
    |> where([b], b.blocker_id == ^identity_id)
    |> select([b], b.blocked_id)
    |> Repo.all()
  end

  # --- Mutes ---

  def mute(muter_id, muted_id, opts \\ []) do
    attrs = %{
      muter_id: muter_id,
      muted_id: muted_id,
      mute_notifications: Keyword.get(opts, :mute_notifications, true),
      expires_at: Keyword.get(opts, :expires_at)
    }

    %Mute{}
    |> Mute.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:mute_notifications, :expires_at, :updated_at]},
      conflict_target: [:muter_id, :muted_id],
      returning: true
    )
  end

  def unmute(muter_id, muted_id) do
    Mute
    |> where([m], m.muter_id == ^muter_id and m.muted_id == ^muted_id)
    |> Repo.delete_all()

    :ok
  end

  def muted?(muter_id, muted_id) do
    now = DateTime.utc_now()

    Mute
    |> where([m], m.muter_id == ^muter_id and m.muted_id == ^muted_id)
    |> where([m], is_nil(m.expires_at) or m.expires_at > ^now)
    |> Repo.exists?()
  end

  def muted_ids(identity_id) do
    now = DateTime.utc_now()

    Mute
    |> where([m], m.muter_id == ^identity_id)
    |> where([m], is_nil(m.expires_at) or m.expires_at > ^now)
    |> select([m], m.muted_id)
    |> Repo.all()
  end

  # --- Relationships ---

  def relationships(identity_id, target_ids) when is_list(target_ids) do
    following_ids =
      Follow
      |> where(
        [f],
        f.follower_id == ^identity_id and f.followee_id in ^target_ids and f.status == :accepted
      )
      |> select([f], f.followee_id)
      |> Repo.all()
      |> MapSet.new()

    followed_by_ids =
      Follow
      |> where(
        [f],
        f.followee_id == ^identity_id and f.follower_id in ^target_ids and f.status == :accepted
      )
      |> select([f], f.follower_id)
      |> Repo.all()
      |> MapSet.new()

    requested_ids =
      Follow
      |> where(
        [f],
        f.follower_id == ^identity_id and f.followee_id in ^target_ids and f.status == :pending
      )
      |> select([f], f.followee_id)
      |> Repo.all()
      |> MapSet.new()

    blocked_ids_set =
      Block
      |> where([b], b.blocker_id == ^identity_id and b.blocked_id in ^target_ids)
      |> select([b], b.blocked_id)
      |> Repo.all()
      |> MapSet.new()

    blocked_by_ids =
      Block
      |> where([b], b.blocked_id == ^identity_id and b.blocker_id in ^target_ids)
      |> select([b], b.blocker_id)
      |> Repo.all()
      |> MapSet.new()

    muted_ids_set =
      Mute
      |> where([m], m.muter_id == ^identity_id and m.muted_id in ^target_ids)
      |> where([m], is_nil(m.expires_at) or m.expires_at > ^DateTime.utc_now())
      |> select([m], m.muted_id)
      |> Repo.all()
      |> MapSet.new()

    Enum.map(target_ids, fn target_id ->
      %{
        id: target_id,
        following: MapSet.member?(following_ids, target_id),
        followed_by: MapSet.member?(followed_by_ids, target_id),
        requested: MapSet.member?(requested_ids, target_id),
        blocking: MapSet.member?(blocked_ids_set, target_id),
        blocked_by: MapSet.member?(blocked_by_ids, target_id),
        muting: MapSet.member?(muted_ids_set, target_id)
      }
    end)
  end
end
