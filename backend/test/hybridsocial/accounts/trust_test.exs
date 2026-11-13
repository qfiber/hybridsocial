defmodule Hybridsocial.Accounts.TrustTest do
  use Hybridsocial.DataCase, async: true

  alias Hybridsocial.Accounts.{Identity, Trust, TrustLevelWorker}
  alias Hybridsocial.Messaging
  alias Hybridsocial.Repo
  alias Hybridsocial.Social.{Follow, Posts}

  defp age(identity, hours) do
    inserted_at = DateTime.add(DateTime.utc_now(), -hours * 3600, :second)
    identity |> Ecto.Changeset.change(inserted_at: inserted_at) |> Repo.update!()
  end

  defp follow!(follower, followee) do
    %Follow{}
    |> Follow.changeset(%{follower_id: follower.id, followee_id: followee.id, status: :accepted})
    |> Repo.insert!()
  end

  defp post!(identity, content \\ "hello") do
    {:ok, post} = Posts.create_post(identity.id, %{"content" => content})
    post
  end

  describe "compute_trust_level/1" do
    test "a brand-new account is level 0" do
      assert Trust.compute_trust_level(create_user("fresh")) == 0
    end

    test "a day old with a post is level 1" do
      identity = create_user("dayold") |> age(25)
      post!(identity)
      assert Trust.compute_trust_level(identity) == 1
    end

    test "a week old with posts and followers is level 2" do
      identity = create_user("weekold") |> age(8 * 24)
      for _ <- 1..5, do: post!(identity)
      follow!(create_user("fan1"), identity)
      follow!(create_user("fan2"), identity)
      assert Trust.compute_trust_level(identity) == 2
    end

    test "pending follow requests don't count" do
      identity = create_user("lockedish") |> age(8 * 24)
      for _ <- 1..5, do: post!(identity)
      follow!(create_user("fan3"), identity)

      %Follow{}
      |> Follow.changeset(%{
        follower_id: create_user("asker").id,
        followee_id: identity.id,
        status: :pending
      })
      |> Repo.insert!()

      assert Trust.compute_trust_level(identity) == 1
    end
  end

  describe "refresh_trust_level/1" do
    test "persists a changed level" do
      identity = create_user("climber") |> age(25)
      post!(identity)
      assert {:ok, %Identity{trust_level: 1}} = Trust.refresh_trust_level(identity)
      assert Repo.get!(Identity, identity.id).trust_level == 1
    end

    test "leaves a staff-pinned level alone" do
      identity =
        create_user("pinned")
        |> Ecto.Changeset.change(trust_level: 4, trust_level_locked: true)
        |> Repo.update!()

      assert {:ok, %Identity{trust_level: 4}} = Trust.refresh_trust_level(identity)
    end
  end

  describe "link gate" do
    test "a new account can't post a link" do
      identity = create_user("linkspam")

      for content <- ["buy at https://spam.example", "see www.spam.example now"] do
        assert {:error, :trust_links_not_allowed} =
                 Posts.create_post(identity.id, %{"content" => content}, identity)
      end

      assert {:error, :trust_links_not_allowed} =
               Posts.create_post(
                 identity.id,
                 %{"content" => "hi", "spoiler_text" => "http://x.example"},
                 identity
               )
    end

    test "a new account can still post plain text" do
      identity = create_user("plainnew")
      assert {:ok, _} = Posts.create_post(identity.id, %{"content" => "hello"}, identity)
    end

    test "the gate lifts as soon as the account qualifies, without waiting for the sweep" do
      identity = create_user("graduate") |> age(25)
      post!(identity)
      assert identity.trust_level == 0

      assert {:ok, _} =
               Posts.create_post(identity.id, %{"content" => "https://ok.example"}, identity)

      assert Repo.get!(Identity, identity.id).trust_level == 1
    end

    test "an edit can't sneak a link in" do
      identity = create_user("editsneak")
      {:ok, post} = Posts.create_post(identity.id, %{"content" => "innocent"}, identity)

      assert {:error, :trust_links_not_allowed} =
               Posts.edit_post(
                 post.id,
                 identity.id,
                 %{"content" => "https://x.example"},
                 identity
               )
    end

    test "staff are never gated" do
      mod = create_moderator("newmod")

      assert {:ok, _} =
               Posts.create_post(mod.id, %{"content" => "rules: https://x.example"}, mod)
    end

    test "a level pinned at 0 stays gated even when the account qualifies" do
      identity =
        create_user("pinnedzero")
        |> age(25)
        |> Ecto.Changeset.change(trust_level_locked: true)
        |> Repo.update!()

      post!(identity)

      assert {:error, :trust_links_not_allowed} =
               Posts.create_post(identity.id, %{"content" => "https://x.example"}, identity)
    end

    test "a subaccount is judged by its owner" do
      owner = create_user("trustedowner") |> age(25)
      post!(owner)

      child =
        create_user("childbot")
        |> Ecto.Changeset.change(parent_identity_id: owner.id)
        |> Repo.update!()

      assert {:ok, _} =
               Posts.create_post(child.id, %{"content" => "feed: https://x.example"}, child)
    end
  end

  describe "direct-post gate" do
    test "a new account can't send a direct post to someone who doesn't follow it" do
      sender = create_user("dmspammer")
      create_user("stranger")

      assert {:error, :trust_dm_not_allowed} =
               Posts.create_post(
                 sender.id,
                 %{"content" => "@stranger hi", "visibility" => "direct"},
                 sender
               )
    end

    test "a new account can send a direct post to a follower" do
      sender = create_user("newbie")
      friend = create_user("friend")
      follow!(friend, sender)

      assert {:ok, _} =
               Posts.create_post(
                 sender.id,
                 %{"content" => "@friend hi", "visibility" => "direct"},
                 sender
               )
    end
  end

  describe "DM gate" do
    test "a new account can't start a DM with a stranger" do
      sender = create_user("dmnew")
      stranger = create_user("dmstranger")

      assert {:error, :trust_dm_not_allowed} =
               Messaging.find_or_create_direct(sender.id, stranger.id)
    end

    test "a new account can DM someone who follows it" do
      sender = create_user("dmnew2")
      friend = create_user("dmfriend")
      follow!(friend, sender)

      assert {:ok, _} = Messaging.find_or_create_direct(sender.id, friend.id)
    end

    test "a new account can answer a conversation someone else started" do
      newbie = create_user("dmnew3")
      elder = create_user("dmelder") |> age(25)
      post!(elder)

      assert {:ok, conv} = Messaging.find_or_create_direct(elder.id, newbie.id)
      assert {:ok, %{id: id}} = Messaging.find_or_create_direct(newbie.id, elder.id)
      assert id == conv.id
    end

    test "a new account can't start a group DM with strangers" do
      sender = create_user("groupnew")

      assert {:error, :trust_dm_not_allowed} =
               Messaging.create_group_dm(sender.id, [create_user("g1").id, create_user("g2").id])
    end
  end

  describe "TrustLevelWorker.run/0" do
    test "promotes accounts that have aged into a level" do
      identity = create_user("sweepme") |> age(25)
      post!(identity)
      assert TrustLevelWorker.run() >= 1
      assert Repo.get!(Identity, identity.id).trust_level == 1
    end
  end

  test "trust_restrictions/1 reports the gates to the client" do
    assert %{link_posting: false, dm_non_followers: false} =
             Trust.trust_restrictions(create_user("restricted"))

    elder = create_user("unrestricted") |> Ecto.Changeset.change(trust_level: 1) |> Repo.update!()
    assert %{link_posting: true, dm_non_followers: true} = Trust.trust_restrictions(elder)
  end
end
