defmodule Hybridsocial.Search.IndexerTest do
  use ExUnit.Case, async: false

  alias Hybridsocial.Search.{Indexer, OpenSearch}

  @posts_index "hybridsocial_posts"
  @accounts_index "hybridsocial_accounts"
  @hashtags_index "hybridsocial_hashtags"
  @groups_index "hybridsocial_groups"

  setup do
    case HTTPoison.get("http://localhost:9200") do
      {:ok, %{status_code: 200}} ->
        # Clean up indexes
        OpenSearch.delete_index(@posts_index)
        OpenSearch.delete_index(@accounts_index)
        OpenSearch.delete_index(@hashtags_index)
        OpenSearch.delete_index(@groups_index)

        on_exit(fn ->
          OpenSearch.delete_index(@posts_index)
          OpenSearch.delete_index(@accounts_index)
          OpenSearch.delete_index(@hashtags_index)
          OpenSearch.delete_index(@groups_index)
        end)

        :ok

      _ ->
        {:skip, "OpenSearch not available"}
    end
  end

  describe "setup_indexes/0" do
    test "creates all required indexes" do
      assert :ok = Indexer.setup_indexes()

      assert OpenSearch.index_exists?(@posts_index)
      assert OpenSearch.index_exists?(@accounts_index)
      assert OpenSearch.index_exists?(@hashtags_index)
      assert OpenSearch.index_exists?(@groups_index)
    end

    test "is idempotent" do
      assert :ok = Indexer.setup_indexes()
      assert :ok = Indexer.setup_indexes()
    end
  end

  describe "index_post/1" do
    setup do
      Indexer.setup_indexes()
      :ok
    end

    test "indexes a post document" do
      post = %Hybridsocial.Social.Post{
        id: Ecto.UUID.generate(),
        content: "Hello from OpenSearch test!",
        identity_id: Ecto.UUID.generate(),
        visibility: "public",
        post_type: "text",
        language: "en",
        reaction_count: 5,
        boost_count: 2,
        reply_count: 1,
        published_at: DateTime.utc_now() |> DateTime.truncate(:microsecond),
        inserted_at: DateTime.utc_now() |> DateTime.truncate(:microsecond),
        identity: %Hybridsocial.Accounts.Identity{
          id: Ecto.UUID.generate(),
          handle: "testuser",
          display_name: "Test User"
        }
      }

      assert :ok = Indexer.index_post(post)
    end
  end

  describe "index_identity/1" do
    setup do
      Indexer.setup_indexes()
      :ok
    end

    test "indexes an identity document" do
      identity = %Hybridsocial.Accounts.Identity{
        id: Ecto.UUID.generate(),
        handle: "testuser",
        display_name: "Test User",
        bio: "A test bio",
        type: "user",
        is_bot: false
      }

      assert :ok = Indexer.index_identity(identity)
    end
  end

  describe "index_group/1" do
    setup do
      Indexer.setup_indexes()
      :ok
    end

    test "indexes a group document" do
      group = %Hybridsocial.Groups.Group{
        id: Ecto.UUID.generate(),
        name: "Test Group",
        description: "A test group",
        visibility: :public,
        join_policy: :open,
        member_count: 10,
        post_count: 5
      }

      assert :ok = Indexer.index_group(group)
    end
  end

  describe "index_hashtag/1" do
    setup do
      Indexer.setup_indexes()
      :ok
    end

    test "indexes a hashtag document" do
      hashtag = %Hybridsocial.Social.Hashtag{
        id: Ecto.UUID.generate(),
        name: "elixir",
        usage_count: 42
      }

      assert :ok = Indexer.index_hashtag(hashtag)
    end
  end

  describe "remove_post/1" do
    setup do
      Indexer.setup_indexes()
      :ok
    end

    test "removes a post from the index" do
      post_id = Ecto.UUID.generate()

      post = %Hybridsocial.Social.Post{
        id: post_id,
        content: "To be removed",
        identity_id: Ecto.UUID.generate(),
        visibility: "public",
        post_type: "text",
        reaction_count: 0,
        boost_count: 0,
        reply_count: 0,
        published_at: DateTime.utc_now() |> DateTime.truncate(:microsecond),
        inserted_at: DateTime.utc_now() |> DateTime.truncate(:microsecond),
        identity: %Hybridsocial.Accounts.Identity{
          id: Ecto.UUID.generate(),
          handle: "testuser",
          display_name: "Test User"
        }
      }

      Indexer.index_post(post)
      assert :ok = Indexer.remove_post(post_id)
    end
  end

  describe "remove_identity/1" do
    setup do
      Indexer.setup_indexes()
      :ok
    end

    test "removes an identity from the index" do
      identity_id = Ecto.UUID.generate()

      identity = %Hybridsocial.Accounts.Identity{
        id: identity_id,
        handle: "toremove",
        display_name: "Remove Me",
        bio: "Gone",
        type: "user",
        is_bot: false
      }

      Indexer.index_identity(identity)
      assert :ok = Indexer.remove_identity(identity_id)
    end
  end
end
