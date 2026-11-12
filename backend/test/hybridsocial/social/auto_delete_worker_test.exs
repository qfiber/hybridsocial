defmodule Hybridsocial.Social.AutoDeleteWorkerTest do
  use Hybridsocial.DataCase, async: true

  import Ecto.Query

  alias Hybridsocial.Accounts
  alias Hybridsocial.Accounts.Identity
  alias Hybridsocial.Repo
  alias Hybridsocial.Social.{AutoDeleteWorker, Post, Posts}

  defp post_at(identity, published_at) do
    {:ok, post} = Posts.create_post(identity.id, %{"content" => "hi", "visibility" => "public"})

    Post
    |> where([p], p.id == ^post.id)
    |> Repo.update_all(set: [published_at: published_at])

    post.id
  end

  defp enable(identity, months, enabled_at) do
    {:ok, identity} =
      Accounts.update_identity(identity, %{"auto_delete_after_months" => months})

    Identity
    |> where([i], i.id == ^identity.id)
    |> Repo.update_all(set: [auto_delete_enabled_at: enabled_at])
  end

  defp deleted?(post_id), do: Repo.get!(Post, post_id).deleted_at != nil

  defp months_ago(now, m), do: DateTime.shift(now, month: -m)

  describe "update_changeset auto-delete fields" do
    test "is off by default" do
      identity = create_user("adoff", "adoff@test.com")
      assert identity.auto_delete_after_months == nil
      assert identity.auto_delete_enabled_at == nil
    end

    test "turning it on stamps enabled_at, off clears it, changing months keeps it" do
      identity = create_user("adtoggle", "adtoggle@test.com")

      {:ok, on} = Accounts.update_identity(identity, %{"auto_delete_after_months" => 3})
      assert on.auto_delete_after_months == 3
      assert %DateTime{} = stamp = on.auto_delete_enabled_at

      {:ok, changed} = Accounts.update_identity(on, %{"auto_delete_after_months" => 6})
      assert changed.auto_delete_enabled_at == stamp

      {:ok, off} = Accounts.update_identity(changed, %{"auto_delete_after_months" => nil})
      assert off.auto_delete_after_months == nil
      assert off.auto_delete_enabled_at == nil
    end

    test "rejects values outside 1..12" do
      identity = create_user("adrange", "adrange@test.com")

      for bad <- [0, 13, -1] do
        assert {:error, cs} =
                 Accounts.update_identity(identity, %{"auto_delete_after_months" => bad})

        assert errors_on(cs)[:auto_delete_after_months]
      end
    end

    test "enabled_at cannot be set from params" do
      identity = create_user("adparam", "adparam@test.com")

      {:ok, updated} =
        Accounts.update_identity(identity, %{"auto_delete_enabled_at" => "2020-01-01T00:00:00Z"})

      assert updated.auto_delete_enabled_at == nil
    end
  end

  describe "run/1" do
    test "deletes posts older than the period, published after enabling" do
      now = DateTime.utc_now()
      identity = create_user("adsweep", "adsweep@test.com")

      before_enabled = post_at(identity, months_ago(now, 10))
      old = post_at(identity, months_ago(now, 3))
      fresh = post_at(identity, months_ago(now, 1))

      enable(identity, 2, months_ago(now, 6))

      assert AutoDeleteWorker.run(now) == 1
      assert deleted?(old)
      refute deleted?(fresh)
      refute deleted?(before_enabled)
    end

    test "does nothing for users who have not enabled it" do
      now = DateTime.utc_now()
      identity = create_user("adnone", "adnone@test.com")
      old = post_at(identity, months_ago(now, 13))

      assert AutoDeleteWorker.run(now) == 0
      refute deleted?(old)
    end
  end
end
