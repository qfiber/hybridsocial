defmodule Hybridsocial.Social do
  @moduledoc """
  The Social context. Manages follows, blocks, and mutes between identities.
  """
  import Ecto.Query
  require Logger

  alias Hybridsocial.Repo
  alias Hybridsocial.Accounts
  alias Hybridsocial.Social.{Follow, Block, Mute, PostMute, UserDomainBlock, AccountNote, FollowedTag, Hashtag, UserContentFilter}
  alias Hybridsocial.Federation.{ActivityBuilder, Publisher}

  # --- Follows ---

  def follow(follower_id, followee_id) do
    with {:not_self, true} <- {:not_self, follower_id != followee_id},
         {:not_blocked, false} <- {:not_blocked, blocked?(followee_id, follower_id)},
         target when not is_nil(target) <- Accounts.get_identity(followee_id) do
      status = if target.is_locked, do: :pending, else: :accepted

      result =
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

      # Publish Follow activity to remote instance if target is remote
      case result do
        {:ok, _follow} ->
          follower = Accounts.get_identity(follower_id)

          if follower && remote?(target) do
            Logger.info("Publishing Follow activity to #{target.ap_actor_url}")

            Task.Supervisor.start_child(Hybridsocial.Federation.DeliveryTaskSupervisor, fn ->
              activity = ActivityBuilder.build_follow(follower, target.ap_actor_url)
              Publisher.publish(activity, follower)
            end)
          else
            Logger.debug("Skipping federation: follower=#{inspect(!!follower)} remote=#{inspect(remote?(target))} ap_url=#{inspect(target.ap_actor_url)}")
          end

        _ ->
          :ok
      end

      result
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

    # Publish Undo Follow to remote instance
    with follower when not is_nil(follower) <- Accounts.get_identity(follower_id),
         target when not is_nil(target) <- Accounts.get_identity(followee_id),
         true <- remote?(target) do
      Task.Supervisor.start_child(Hybridsocial.Federation.DeliveryTaskSupervisor, fn ->
        follow_activity = ActivityBuilder.build_follow(follower, target.ap_actor_url)
        activity = ActivityBuilder.build_undo(follower, follow_activity)
        Publisher.publish(activity, follower)
      end)
    end

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

  @doc "Accounts that the viewer follows who also follow the target account."
  def familiar_followers(viewer_id, target_id) do
    # People the viewer follows
    viewer_following =
      Follow
      |> where([f], f.follower_id == ^viewer_id and f.status == :accepted)
      |> select([f], f.followee_id)

    # Of those, who follows the target?
    Follow
    |> where([f], f.follower_id in subquery(viewer_following))
    |> where([f], f.followee_id == ^target_id and f.status == :accepted)
    |> join(:inner, [f], i in Hybridsocial.Accounts.Identity, on: i.id == f.follower_id and is_nil(i.deleted_at))
    |> select([f, i], i)
    |> limit(5)
    |> Repo.all()
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

  # --- Post Mutes (mute notifications from a specific post) ---

  def mute_post(post_id, identity_id) do
    %PostMute{}
    |> PostMute.changeset(%{post_id: post_id, identity_id: identity_id})
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:post_id, :identity_id])
  end

  def unmute_post(post_id, identity_id) do
    PostMute
    |> where([pm], pm.post_id == ^post_id and pm.identity_id == ^identity_id)
    |> Repo.delete_all()

    :ok
  end

  def post_muted?(post_id, identity_id) do
    PostMute
    |> where([pm], pm.post_id == ^post_id and pm.identity_id == ^identity_id)
    |> Repo.exists?()
  end

  # --- Follow Requests ---

  def pending_follow_requests(identity_id) do
    Follow
    |> where([f], f.followee_id == ^identity_id and f.status == :pending)
    |> order_by([f], desc: f.inserted_at)
    |> preload(:follower)
    |> Repo.all()
  end

  # --- Blocked & Muted account lists ---

  def blocked_accounts(identity_id) do
    Block
    |> where([b], b.blocker_id == ^identity_id)
    |> join(:inner, [b], i in Hybridsocial.Accounts.Identity, on: i.id == b.blocked_id)
    |> select([b, i], i)
    |> Repo.all()
  end

  def muted_accounts(identity_id) do
    Mute
    |> where([m], m.muter_id == ^identity_id)
    |> join(:inner, [m], i in Hybridsocial.Accounts.Identity, on: i.id == m.muted_id)
    |> select([m, i], i)
    |> Repo.all()
  end

  # --- User-level domain blocks ---

  def list_domain_blocks(identity_id) do
    UserDomainBlock
    |> where([d], d.identity_id == ^identity_id)
    |> order_by([d], desc: d.inserted_at)
    |> Repo.all()
  end

  def block_domain(identity_id, domain) do
    %UserDomainBlock{}
    |> UserDomainBlock.changeset(%{identity_id: identity_id, domain: domain})
    |> Repo.insert(on_conflict: :nothing)
  end

  def unblock_domain(identity_id, domain) do
    UserDomainBlock
    |> where([d], d.identity_id == ^identity_id and d.domain == ^String.downcase(domain))
    |> Repo.delete_all()
    :ok
  end

  def domain_blocked?(identity_id, domain) do
    UserDomainBlock
    |> where([d], d.identity_id == ^identity_id and d.domain == ^String.downcase(domain))
    |> Repo.exists?()
  end

  # --- Personal account notes ---

  def set_account_note(author_id, target_id, content) do
    %AccountNote{}
    |> AccountNote.changeset(%{author_id: author_id, target_id: target_id, content: content})
    |> Repo.insert(
      on_conflict: {:replace, [:content, :updated_at]},
      conflict_target: [:author_id, :target_id]
    )
  end

  def get_account_note(author_id, target_id) do
    AccountNote
    |> where([n], n.author_id == ^author_id and n.target_id == ^target_id)
    |> Repo.one()
  end

  def delete_account_note(author_id, target_id) do
    AccountNote
    |> where([n], n.author_id == ^author_id and n.target_id == ^target_id)
    |> Repo.delete_all()
    :ok
  end

  # --- Followed Hashtags ---

  def follow_tag(identity_id, tag_name) do
    tag_name = String.downcase(tag_name) |> String.trim_leading("#")

    # Find or create the hashtag
    hashtag =
      case Repo.get_by(Hashtag, name: tag_name) do
        nil ->
          %Hashtag{}
          |> Hashtag.changeset(%{name: tag_name})
          |> Repo.insert!()

        existing ->
          existing
      end

    %FollowedTag{}
    |> FollowedTag.changeset(%{identity_id: identity_id, hashtag_id: hashtag.id})
    |> Repo.insert(on_conflict: :nothing)
    |> case do
      {:ok, ft} -> {:ok, ft}
      {:error, _} -> {:ok, :already_following}
    end
  end

  def unfollow_tag(identity_id, tag_name) do
    tag_name = String.downcase(tag_name) |> String.trim_leading("#")

    case Repo.get_by(Hashtag, name: tag_name) do
      nil -> :ok
      hashtag ->
        FollowedTag
        |> where([ft], ft.identity_id == ^identity_id and ft.hashtag_id == ^hashtag.id)
        |> Repo.delete_all()
        :ok
    end
  end

  def followed_tags(identity_id) do
    FollowedTag
    |> where([ft], ft.identity_id == ^identity_id)
    |> join(:inner, [ft], h in Hashtag, on: h.id == ft.hashtag_id)
    |> select([ft, h], %{id: h.id, name: h.name, following: true})
    |> order_by([ft, h], asc: h.name)
    |> Repo.all()
  end

  def following_tag?(identity_id, tag_name) do
    tag_name = String.downcase(tag_name) |> String.trim_leading("#")

    FollowedTag
    |> join(:inner, [ft], h in Hashtag, on: h.id == ft.hashtag_id)
    |> where([ft, h], ft.identity_id == ^identity_id and h.name == ^tag_name)
    |> Repo.exists?()
  end

  # --- User Content Filters ---

  def list_user_filters(identity_id) do
    UserContentFilter
    |> where([f], f.identity_id == ^identity_id)
    |> where([f], is_nil(f.expires_at) or f.expires_at > ^DateTime.utc_now())
    |> order_by([f], desc: f.inserted_at)
    |> Repo.all()
  end

  def create_user_filter(identity_id, attrs) do
    %UserContentFilter{}
    |> UserContentFilter.changeset(Map.put(attrs, "identity_id", identity_id))
    |> Repo.insert()
  end

  def update_user_filter(filter_id, identity_id, attrs) do
    case Repo.get_by(UserContentFilter, id: filter_id, identity_id: identity_id) do
      nil -> {:error, :not_found}
      filter ->
        filter
        |> UserContentFilter.changeset(attrs)
        |> Repo.update()
    end
  end

  def delete_user_filter(filter_id, identity_id) do
    case Repo.get_by(UserContentFilter, id: filter_id, identity_id: identity_id) do
      nil -> {:error, :not_found}
      filter -> Repo.delete(filter)
    end
  end

  def followed_tag_names(identity_id) do
    FollowedTag
    |> where([ft], ft.identity_id == ^identity_id)
    |> join(:inner, [ft], h in Hashtag, on: h.id == ft.hashtag_id)
    |> select([ft, h], h.name)
    |> Repo.all()
  end

  # --- Boost Muting (mute someone's boosts without muting them) ---

  def mute_boosts(muter_id, target_id) do
    Repo.insert_all("boost_mutes",
      [%{id: Ecto.UUID.generate(), muter_id: Ecto.UUID.dump!(muter_id), target_id: Ecto.UUID.dump!(target_id), inserted_at: DateTime.utc_now(), updated_at: DateTime.utc_now()}],
      on_conflict: :nothing
    )
    :ok
  end

  def unmute_boosts(muter_id, target_id) do
    {:ok, muter_uuid} = Ecto.UUID.dump(muter_id)
    {:ok, target_uuid} = Ecto.UUID.dump(target_id)

    from(bm in "boost_mutes",
      where: bm.muter_id == ^muter_uuid and bm.target_id == ^target_uuid
    )
    |> Repo.delete_all()
    :ok
  end

  def boost_muted?(muter_id, target_id) do
    {:ok, muter_uuid} = Ecto.UUID.dump(muter_id)
    {:ok, target_uuid} = Ecto.UUID.dump(target_id)

    from(bm in "boost_mutes",
      where: bm.muter_id == ^muter_uuid and bm.target_id == ^target_uuid
    )
    |> Repo.exists?()
  end

  def boost_muted_ids(muter_id) do
    {:ok, muter_uuid} = Ecto.UUID.dump(muter_id)

    from(bm in "boost_mutes",
      where: bm.muter_id == ^muter_uuid,
      select: bm.target_id
    )
    |> Repo.all()
    |> Enum.map(fn uuid -> Ecto.UUID.load!(uuid) end)
  end

  # Check if an identity is from a remote instance
  defp remote?(%{ap_actor_url: url}) when is_binary(url) do
    base = HybridsocialWeb.Endpoint.url()
    not String.starts_with?(url, base)
  end

  defp remote?(_), do: false
end
