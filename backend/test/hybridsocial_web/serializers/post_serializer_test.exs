defmodule HybridsocialWeb.Serializers.PostSerializerTest do
  @moduledoc """
  Unit tests for PostSerializer's account block — specifically the
  verification fields that the frontend badge UI keys off.
  """
  use Hybridsocial.DataCase, async: true

  alias HybridsocialWeb.Serializers.PostSerializer

  defp identity(attrs) do
    base = %Hybridsocial.Accounts.Identity{
      id: Ecto.UUID.generate(),
      type: "user",
      handle: "alice",
      display_name: "Alice",
      inserted_at: ~U[2026-01-01 00:00:00.000000Z]
    }

    Map.merge(base, attrs)
  end

  describe "serialize_account/2 verification fields" do
    test "includes verification_tier and is_verified=true for paid tiers" do
      for tier <- ["verified_starter", "verified_creator", "verified_pro"] do
        account = PostSerializer.serialize_account(identity(%{verification_tier: tier}), [])

        assert account.verification_tier == tier
        assert account.is_verified == true
      end
    end

    test "is_verified=false for the free tier" do
      account = PostSerializer.serialize_account(identity(%{verification_tier: "free"}), [])

      assert account.verification_tier == "free"
      assert account.is_verified == false
    end

    test "is_verified=false when verification_tier is nil" do
      account = PostSerializer.serialize_account(identity(%{verification_tier: nil}), [])

      assert account.verification_tier == nil
      assert account.is_verified == false
    end

    test "is_verified=false for unknown tier strings" do
      account = PostSerializer.serialize_account(identity(%{verification_tier: "garbage"}), [])

      assert account.is_verified == false
    end
  end

  describe "serialize_account/2 type translation" do
    test "emits 'page' instead of 'organization' at the API boundary" do
      account = PostSerializer.serialize_account(identity(%{type: "organization"}), [])
      assert account.type == "page"
    end

    test "passes other types through unchanged" do
      for t <- ["user", "bot", "group"] do
        account = PostSerializer.serialize_account(identity(%{type: t}), [])
        assert account.type == t
      end
    end
  end

  describe "remote media attachments" do
    alias Hybridsocial.Media.MediaFile

    test "remote_changeset accepts remote-only attrs (no storage_path)" do
      changeset =
        MediaFile.remote_changeset(%MediaFile{}, %{
          identity_id: Ecto.UUID.generate(),
          post_id: Ecto.UUID.generate(),
          content_type: "image/jpeg",
          remote_url: "https://mastodon.example/system/img/1.jpg",
          remote_origin_domain: "mastodon.example",
          alt_text: "a cat",
          width: 800,
          height: 600
        })

      assert changeset.valid?
      assert changeset.changes.remote_url == "https://mastodon.example/system/img/1.jpg"
      assert changeset.changes.remote_origin_domain == "mastodon.example"
      # storage_path stays nil — that's the marker that bytes live remote.
      refute Map.has_key?(changeset.changes, :storage_path)
    end

    test "remote_changeset rejects missing remote_url" do
      changeset =
        MediaFile.remote_changeset(%MediaFile{}, %{
          identity_id: Ecto.UUID.generate(),
          remote_origin_domain: "mastodon.example"
        })

      refute changeset.valid?
      assert {_, _} = changeset.errors[:remote_url]
    end

    test "remote_changeset rejects missing identity_id" do
      changeset =
        MediaFile.remote_changeset(%MediaFile{}, %{
          remote_url: "https://mastodon.example/system/img/1.jpg",
          remote_origin_domain: "mastodon.example"
        })

      refute changeset.valid?
      assert {_, _} = changeset.errors[:identity_id]
    end
  end

  describe "last_activity_at" do
    alias Hybridsocial.Social.Posts

    test "is exposed so the client can explain an activity-ordered bump" do
      author = create_user("bumpauthor")
      replier = create_user("bumpreplier")

      {:ok, post} =
        Posts.create_post(author.id, %{
          "content" => "Root post",
          "post_type" => "text",
          "visibility" => "public"
        })

      {:ok, _reply} =
        Posts.create_post(replier.id, %{
          "content" => "A reply",
          "post_type" => "text",
          "visibility" => "public",
          "parent_id" => post.id
        })

      bumped = Repo.get!(Hybridsocial.Social.Post, post.id) |> Repo.preload(:identity)
      serialized = PostSerializer.serialize(bumped)

      assert serialized.last_activity_at == bumped.last_activity_at
      # The reply moved it past publication — that gap is what the feed
      # sorts on and what the client renders as "Last reply …".
      assert DateTime.compare(serialized.last_activity_at, bumped.published_at) == :gt
    end

    test "serialize_many exposes it too" do
      author = create_user("bumpauthor2")

      {:ok, post} =
        Posts.create_post(author.id, %{
          "content" => "Unbumped post",
          "post_type" => "text",
          "visibility" => "public"
        })

      reloaded = Repo.get!(Hybridsocial.Social.Post, post.id) |> Repo.preload(:identity)
      [serialized] = PostSerializer.serialize_many([reloaded])

      # Never replied to: last_activity_at is stamped at publication, so the
      # client sees no gap and shows no bump line.
      assert serialized.last_activity_at == post.published_at
    end
  end

  describe "page.can_edit — so the client shows Edit/Delete on your page's posts" do
    alias Hybridsocial.{Pages, Social.Posts}

    setup do
      owner = create_user("pgcanedit_owner", "pgcanedit_owner@test.com")
      stranger = create_user("pgcanedit_stranger", "pgcanedit_stranger@test.com")

      {:ok, page} =
        Pages.create_page(owner.id, %{
          "handle" => "pgcanedit_page",
          "display_name" => "Page",
          "bio" => "b",
          "category" => "tech"
        })

      # Authored as the page: identity_id AND page_id are the page.
      {:ok, post} =
        Posts.create_post(page.id, %{
          "content" => "Hello from the page",
          "visibility" => "public",
          "page_id" => page.id
        })

      reloaded = Repo.get!(Hybridsocial.Social.Post, post.id) |> Repo.preload(:identity)
      %{owner: owner, stranger: stranger, post: reloaded}
    end

    test "true for the page owner (who can edit/delete it)", %{owner: owner, post: post} do
      serialized = PostSerializer.serialize(post, current_identity_id: owner.id)
      assert serialized.page.can_edit == true
    end

    test "false for an unrelated viewer", %{stranger: stranger, post: post} do
      serialized = PostSerializer.serialize(post, current_identity_id: stranger.id)
      assert serialized.page.can_edit == false
    end

    test "false for an anonymous viewer", %{post: post} do
      serialized = PostSerializer.serialize(post)
      assert serialized.page.can_edit == false
    end

    # The prewarmed public/global first page is serialized once with no viewer,
    # so `can_edit` is baked false in the snapshot. apply_viewer_state/2 has to
    # recompute it, or a page's own managers lose Edit/Delete on exactly the
    # timelines that get prewarmed.
    test "apply_viewer_state recomputes it on a prewarmed snapshot", %{
      owner: owner,
      stranger: stranger,
      post: post
    } do
      snapshot =
        [post]
        |> PostSerializer.serialize_many()
        |> round_trip_through_cache()

      assert [%{"page" => %{"can_edit" => false}}] = snapshot

      assert [%{"page" => %{"can_edit" => true}}] =
               PostSerializer.apply_viewer_state(snapshot, owner.id)

      assert [%{"page" => %{"can_edit" => false}}] =
               PostSerializer.apply_viewer_state(snapshot, stranger.id)
    end

    test "apply_viewer_state leaves a post with no page alone", %{owner: owner} do
      {:ok, plain} =
        Posts.create_post(owner.id, %{"content" => "no page", "visibility" => "public"})

      reloaded = Repo.get!(Hybridsocial.Social.Post, plain.id) |> Repo.preload(:identity)

      snapshot = [reloaded] |> PostSerializer.serialize_many() |> round_trip_through_cache()

      assert [patched] = PostSerializer.apply_viewer_state(snapshot, owner.id)
      refute Map.has_key?(patched, "page") and is_map(patched["page"])
    end

    # apply_viewer_state/2 consumes the cache-round-tripped snapshot, which is
    # string-keyed. Mimic that rather than passing atom-keyed structs it would
    # never see in production.
    defp round_trip_through_cache(serialized) do
      serialized |> Jason.encode!() |> Jason.decode!()
    end
  end

  describe "expires_at (#278)" do
    setup do
      user = create_user("autodel", "autodel@example.com")
      {:ok, post} = Hybridsocial.Social.Posts.create_post(user.id, %{"content" => "hi"})
      %{user: user, post: post}
    end

    defp reload(post),
      do: Hybridsocial.Repo.preload(Hybridsocial.Repo.reload!(post), :identity, force: true)

    defp set_auto_delete(user, months, enabled_at) do
      Hybridsocial.Repo.update_all(
        from(i in Hybridsocial.Accounts.Identity, where: i.id == ^user.id),
        set: [auto_delete_after_months: months, auto_delete_enabled_at: enabled_at]
      )
    end

    test "nil when neither a timer nor account auto-delete applies", %{post: post} do
      assert PostSerializer.serialize(reload(post)).expires_at == nil
    end

    test "account auto-delete gives published_at + months, in both paths", %{
      user: user,
      post: post
    } do
      set_auto_delete(user, 3, ~U[2020-01-01 00:00:00.000000Z])
      post = reload(post)
      want = DateTime.shift(post.published_at, month: 3)

      assert PostSerializer.serialize(post).expires_at == want
      assert [%{expires_at: ^want}] = PostSerializer.serialize_many([post])
    end

    test "posts from before the setting was switched on are kept", %{user: user, post: post} do
      set_auto_delete(user, 3, DateTime.add(DateTime.utc_now(), 3600))
      assert PostSerializer.serialize(reload(post)).expires_at == nil
    end

    test "the earlier of the post timer and account auto-delete wins", %{
      user: user,
      post: post
    } do
      set_auto_delete(user, 3, ~U[2020-01-01 00:00:00.000000Z])
      soon = DateTime.add(DateTime.utc_now(), 3600)

      Hybridsocial.Repo.update_all(
        from(p in Hybridsocial.Social.Post, where: p.id == ^post.id),
        set: [expires_at: soon]
      )

      assert PostSerializer.serialize(reload(post)).expires_at == soon
    end
  end
end
