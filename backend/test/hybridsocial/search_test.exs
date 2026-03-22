defmodule Hybridsocial.SearchTest do
  use Hybridsocial.DataCase, async: true

  alias Hybridsocial.Search
  alias Hybridsocial.Social.Posts
  alias Hybridsocial.Groups

  defp create_user(handle, email) do
    {:ok, identity} =
      Hybridsocial.Accounts.register_user(%{
        "handle" => handle,
        "email" => email,
        "password" => "password123",
        "password_confirmation" => "password123"
      })

    identity
  end

  describe "search_accounts/2" do
    test "finds accounts by handle prefix" do
      user = create_user("searchable", "searchable@test.com")
      _other = create_user("another", "another@test.com")

      results = Search.search_accounts("search")
      assert length(results) == 1
      assert hd(results).id == user.id
    end

    test "finds accounts via full-text search on display_name" do
      user = create_user("jdoe", "jdoe@test.com")

      # Update display_name to trigger tsvector update
      Hybridsocial.Repo.update!(Ecto.Changeset.change(user, display_name: "John Doe Developer"))

      results = Search.search_accounts("john")
      assert length(results) >= 1
      assert Enum.any?(results, &(&1.id == user.id))
    end

    test "excludes suspended accounts" do
      user = create_user("suspended_user", "suspended@test.com")

      Hybridsocial.Repo.update!(Ecto.Changeset.change(user, is_suspended: true))

      results = Search.search_accounts("suspended_user")
      assert results == []
    end

    test "excludes soft-deleted accounts" do
      user = create_user("deleted_user", "deleted@test.com")

      Hybridsocial.Repo.update!(Ecto.Changeset.change(user, deleted_at: DateTime.utc_now()))

      results = Search.search_accounts("deleted_user")
      assert results == []
    end

    test "returns empty for blank query" do
      _user = create_user("someone", "someone@test.com")
      assert Search.search_accounts("") == []
      assert Search.search_accounts("   ") == []
    end
  end

  describe "search_posts/3" do
    test "finds posts by content" do
      user = create_user("poster", "poster@test.com")
      {:ok, post} = Posts.create_post(user.id, %{"content" => "Elixir is a great language"})

      results = Search.search_posts("elixir", nil)
      assert length(results) >= 1
      assert Enum.any?(results, &(&1.id == post.id))
    end

    test "excludes soft-deleted posts" do
      user = create_user("poster2", "poster2@test.com")
      {:ok, post} = Posts.create_post(user.id, %{"content" => "Delete this unique content xyzzy"})
      {:ok, _} = Posts.delete_post(post.id, user.id)

      results = Search.search_posts("xyzzy", nil)
      assert results == []
    end

    test "only returns public posts for anonymous viewers" do
      user = create_user("poster3", "poster3@test.com")

      {:ok, _public} =
        Posts.create_post(user.id, %{"content" => "Public zqfmgb post", "visibility" => "public"})

      {:ok, _private} =
        Posts.create_post(user.id, %{
          "content" => "Followers zqfmgb post",
          "visibility" => "followers"
        })

      results = Search.search_posts("zqfmgb", nil)
      assert length(results) == 1
    end

    test "returns own non-public posts to viewer" do
      user = create_user("poster4", "poster4@test.com")

      {:ok, _private} =
        Posts.create_post(user.id, %{
          "content" => "My private wqkjzn thoughts",
          "visibility" => "followers"
        })

      results = Search.search_posts("wqkjzn", user.id)
      assert length(results) == 1
    end

    test "filters by account_id" do
      user1 = create_user("author1", "author1@test.com")
      user2 = create_user("author2", "author2@test.com")
      {:ok, _p1} = Posts.create_post(user1.id, %{"content" => "Testing qwrtyp from author1"})
      {:ok, _p2} = Posts.create_post(user2.id, %{"content" => "Testing qwrtyp from author2"})

      results = Search.search_posts("qwrtyp", nil, account_id: user1.id)
      assert length(results) == 1
    end
  end

  describe "search_hashtags/2" do
    test "finds hashtags by partial name" do
      user = create_user("tagger", "tagger@test.com")
      {:ok, _} = Posts.create_post(user.id, %{"content" => "Hello #elixirlang rocks"})

      results = Search.search_hashtags("elixir")
      assert length(results) >= 1
      assert Enum.any?(results, &(&1.name == "elixirlang"))
    end

    test "returns empty for blank query" do
      assert Search.search_hashtags("") == []
    end
  end

  describe "search_groups/2" do
    test "finds groups by name" do
      user = create_user("grouper", "grouper@test.com")

      {:ok, group} =
        Groups.create_group(user.id, %{
          "name" => "Elixir Enthusiasts",
          "description" => "A group for Elixir fans"
        })

      results = Search.search_groups("Elixir Enthus")
      assert length(results) >= 1
      assert Enum.any?(results, &(&1.id == group.id))
    end

    test "finds groups by description" do
      user = create_user("grouper2", "grouper2@test.com")

      {:ok, group} =
        Groups.create_group(user.id, %{
          "name" => "Phoenix Club",
          "description" => "We discuss the zmbrqx framework"
        })

      results = Search.search_groups("zmbrqx")
      assert length(results) >= 1
      assert Enum.any?(results, &(&1.id == group.id))
    end

    test "excludes local_only groups for anonymous viewers" do
      user = create_user("grouper3", "grouper3@test.com")

      {:ok, _group} =
        Groups.create_group(user.id, %{
          "name" => "Secret vqxnwp Group",
          "visibility" => "local_only"
        })

      results = Search.search_groups("vqxnwp")
      assert results == []
    end
  end

  describe "search/2 unified" do
    test "returns results across all types" do
      user = create_user("unifinder", "unifinder@test.com")
      {:ok, _post} = Posts.create_post(user.id, %{"content" => "unifinder post content"})

      results = Search.search("unifinder")
      assert is_list(results.accounts)
      assert is_list(results.posts)
      assert is_list(results.hashtags)
      assert is_list(results.groups)
      assert length(results.accounts) >= 1
    end

    test "filters by type when specified" do
      user = create_user("typefilter", "typefilter@test.com")
      {:ok, _post} = Posts.create_post(user.id, %{"content" => "typefilter post"})

      results = Search.search("typefilter", type: "accounts")
      assert length(results.accounts) >= 1
      assert results.posts == []
      assert results.hashtags == []
      assert results.groups == []
    end
  end
end
