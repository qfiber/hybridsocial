defmodule Hybridsocial.Social.ListsTest do
  use Hybridsocial.DataCase, async: false

  alias Hybridsocial.Social.Lists

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp create_user(handle, email) do
    {:ok, identity} =
      Hybridsocial.Accounts.register_user(%{
        "handle" => handle,
        "email" => email,
        "password" => "Password123!!",
        "password_confirmation" => "Password123!!"
      })

    identity
  end

  # ---------------------------------------------------------------------------
  # List CRUD
  # ---------------------------------------------------------------------------

  describe "create_list/2" do
    test "creates a list for the identity" do
      alice = create_user("list_alice", "list_alice@example.com")

      assert {:ok, list} = Lists.create_list(alice.id, "My List")
      assert list.name == "My List"
      assert list.identity_id == alice.id
    end

    test "fails with missing name" do
      alice = create_user("list_alice2", "list_alice2@example.com")

      assert {:error, _changeset} = Lists.create_list(alice.id, "")
    end
  end

  describe "get_list/1" do
    test "returns the list by id" do
      alice = create_user("list_get", "list_get@example.com")
      {:ok, list} = Lists.create_list(alice.id, "Test List")

      assert Lists.get_list(list.id) != nil
      assert Lists.get_list(list.id).name == "Test List"
    end

    test "returns nil for non-existent list" do
      assert Lists.get_list(Ecto.UUID.generate()) == nil
    end
  end

  describe "get_lists/1" do
    test "returns all lists for the identity" do
      alice = create_user("list_all", "list_all@example.com")
      {:ok, _} = Lists.create_list(alice.id, "List A")
      {:ok, _} = Lists.create_list(alice.id, "List B")

      lists = Lists.get_lists(alice.id)
      assert length(lists) == 2
      names = Enum.map(lists, & &1.name)
      assert "List A" in names
      assert "List B" in names
    end

    test "does not return other users lists" do
      alice = create_user("list_own1", "list_own1@example.com")
      bob = create_user("list_own2", "list_own2@example.com")
      {:ok, _} = Lists.create_list(alice.id, "Alice's List")
      {:ok, _} = Lists.create_list(bob.id, "Bob's List")

      alice_lists = Lists.get_lists(alice.id)
      assert length(alice_lists) == 1
      assert hd(alice_lists).name == "Alice's List"
    end
  end

  describe "update_list/3" do
    test "updates the list name" do
      alice = create_user("list_upd", "list_upd@example.com")
      {:ok, list} = Lists.create_list(alice.id, "Old Name")

      assert {:ok, updated} = Lists.update_list(list.id, alice.id, %{"name" => "New Name"})
      assert updated.name == "New Name"
    end

    test "returns error when not the owner" do
      alice = create_user("list_upd2", "list_upd2@example.com")
      bob = create_user("list_upd3", "list_upd3@example.com")
      {:ok, list} = Lists.create_list(alice.id, "Alice's List")

      assert {:error, :not_found} = Lists.update_list(list.id, bob.id, %{"name" => "Hacked"})
    end
  end

  describe "delete_list/2" do
    test "deletes the list" do
      alice = create_user("list_del", "list_del@example.com")
      {:ok, list} = Lists.create_list(alice.id, "Deletable")

      assert {:ok, _} = Lists.delete_list(list.id, alice.id)
      assert Lists.get_list(list.id) == nil
    end

    test "returns error when not the owner" do
      alice = create_user("list_del2", "list_del2@example.com")
      bob = create_user("list_del3", "list_del3@example.com")
      {:ok, list} = Lists.create_list(alice.id, "Alice's List")

      assert {:error, :not_found} = Lists.delete_list(list.id, bob.id)
    end
  end

  # ---------------------------------------------------------------------------
  # Membership
  # ---------------------------------------------------------------------------

  describe "add_to_list/3" do
    test "adds a member to the list" do
      alice = create_user("list_add1", "list_add1@example.com")
      bob = create_user("list_add2", "list_add2@example.com")
      {:ok, list} = Lists.create_list(alice.id, "Friends")

      assert {:ok, _member} = Lists.add_to_list(list.id, alice.id, bob.id)

      members = Lists.list_members(list.id)
      assert length(members) == 1
      assert hd(members).target_identity_id == bob.id
    end

    test "returns error when not the owner" do
      alice = create_user("list_add3", "list_add3@example.com")
      bob = create_user("list_add4", "list_add4@example.com")
      carol = create_user("list_add5", "list_add5@example.com")
      {:ok, list} = Lists.create_list(alice.id, "Friends")

      assert {:error, :not_found} = Lists.add_to_list(list.id, bob.id, carol.id)
    end

    test "rejects duplicate membership" do
      alice = create_user("list_dup1", "list_dup1@example.com")
      bob = create_user("list_dup2", "list_dup2@example.com")
      {:ok, list} = Lists.create_list(alice.id, "Friends")

      assert {:ok, _} = Lists.add_to_list(list.id, alice.id, bob.id)
      assert {:error, _} = Lists.add_to_list(list.id, alice.id, bob.id)
    end
  end

  describe "remove_from_list/3" do
    test "removes a member from the list" do
      alice = create_user("list_rm1", "list_rm1@example.com")
      bob = create_user("list_rm2", "list_rm2@example.com")
      {:ok, list} = Lists.create_list(alice.id, "Friends")
      {:ok, _} = Lists.add_to_list(list.id, alice.id, bob.id)

      assert :ok = Lists.remove_from_list(list.id, alice.id, bob.id)
      assert Lists.list_members(list.id) == []
    end

    test "returns error when not the owner" do
      alice = create_user("list_rm3", "list_rm3@example.com")
      bob = create_user("list_rm4", "list_rm4@example.com")
      {:ok, list} = Lists.create_list(alice.id, "Friends")
      {:ok, _} = Lists.add_to_list(list.id, alice.id, bob.id)

      assert {:error, :not_found} = Lists.remove_from_list(list.id, bob.id, bob.id)
    end
  end

  describe "list_members/1" do
    test "returns all members with preloaded identities" do
      alice = create_user("list_mem1", "list_mem1@example.com")
      bob = create_user("list_mem2", "list_mem2@example.com")
      carol = create_user("list_mem3", "list_mem3@example.com")
      {:ok, list} = Lists.create_list(alice.id, "Friends")

      {:ok, _} = Lists.add_to_list(list.id, alice.id, bob.id)
      {:ok, _} = Lists.add_to_list(list.id, alice.id, carol.id)

      members = Lists.list_members(list.id)
      assert length(members) == 2

      member_ids = Enum.map(members, & &1.target_identity_id)
      assert bob.id in member_ids
      assert carol.id in member_ids
    end

    test "returns empty list for empty list" do
      alice = create_user("list_mem4", "list_mem4@example.com")
      {:ok, list} = Lists.create_list(alice.id, "Empty")

      assert Lists.list_members(list.id) == []
    end
  end
end
