defmodule Hybridsocial.Search.OpenSearchTest do
  use ExUnit.Case, async: false

  alias Hybridsocial.Search.OpenSearch

  @test_index "hybridsocial_test_opensearch"

  setup do
    case HTTPoison.get("http://localhost:9200") do
      {:ok, %{status_code: 200}} ->
        # Clean up test index before each test
        OpenSearch.delete_index(@test_index)
        on_exit(fn -> OpenSearch.delete_index(@test_index) end)
        :ok

      _ ->
        :ok
    end
  end

  @moduletag :opensearch

  describe "index management" do
    test "create_index/2 creates an index with mapping" do
      mapping = %{
        mappings: %{
          properties: %{
            title: %{type: "text"},
            count: %{type: "integer"}
          }
        }
      }

      assert :ok = OpenSearch.create_index(@test_index, mapping)
      assert OpenSearch.index_exists?(@test_index)
    end

    test "create_index/2 is idempotent" do
      mapping = %{mappings: %{properties: %{title: %{type: "text"}}}}

      assert :ok = OpenSearch.create_index(@test_index, mapping)
      assert :ok = OpenSearch.create_index(@test_index, mapping)
    end

    test "delete_index/1 removes an index" do
      mapping = %{mappings: %{properties: %{title: %{type: "text"}}}}
      OpenSearch.create_index(@test_index, mapping)

      assert :ok = OpenSearch.delete_index(@test_index)
      refute OpenSearch.index_exists?(@test_index)
    end

    test "delete_index/1 succeeds for non-existent index" do
      assert :ok = OpenSearch.delete_index("nonexistent_index_xyz")
    end

    test "index_exists?/1 returns false for non-existent index" do
      refute OpenSearch.index_exists?("nonexistent_index_xyz")
    end
  end

  describe "document operations" do
    setup do
      mapping = %{
        mappings: %{
          properties: %{
            title: %{type: "text"},
            content: %{type: "text"},
            count: %{type: "integer"}
          }
        }
      }

      OpenSearch.create_index(@test_index, mapping)
      :ok
    end

    test "index_document/3 indexes a document" do
      doc = %{title: "Test Doc", content: "Hello world", count: 1}
      assert :ok = OpenSearch.index_document(@test_index, "doc1", doc)
    end

    test "delete_document/2 removes a document" do
      doc = %{title: "Test Doc", content: "Hello world", count: 1}
      OpenSearch.index_document(@test_index, "doc1", doc)

      assert :ok = OpenSearch.delete_document(@test_index, "doc1")
    end

    test "delete_document/2 succeeds for non-existent document" do
      assert :ok = OpenSearch.delete_document(@test_index, "nonexistent")
    end

    test "bulk_index/2 indexes multiple documents" do
      docs = [
        %{id: "b1", title: "Bulk 1", content: "First", count: 1},
        %{id: "b2", title: "Bulk 2", content: "Second", count: 2},
        %{id: "b3", title: "Bulk 3", content: "Third", count: 3}
      ]

      assert :ok = OpenSearch.bulk_index(@test_index, docs)
    end

    test "bulk_index/2 with empty list returns :ok" do
      assert :ok = OpenSearch.bulk_index(@test_index, [])
    end
  end

  describe "search" do
    setup do
      mapping = %{
        mappings: %{
          properties: %{
            title: %{type: "text"},
            content: %{type: "text"},
            category: %{type: "keyword"}
          }
        }
      }

      OpenSearch.create_index(@test_index, mapping)

      docs = [
        %{id: "s1", title: "Elixir Programming", content: "Learn Elixir", category: "tech"},
        %{
          id: "s2",
          title: "Phoenix Framework",
          content: "Build web apps with Phoenix",
          category: "tech"
        },
        %{id: "s3", title: "Cooking Guide", content: "How to cook pasta", category: "food"}
      ]

      OpenSearch.bulk_index(@test_index, docs)

      # Wait for indexing to complete
      :timer.sleep(1500)
      # Force refresh
      HTTPoison.post("http://localhost:9200/#{@test_index}/_refresh", "", [
        {"Content-Type", "application/json"}
      ])

      :ok
    end

    test "search/3 returns matching documents" do
      query = %{query: %{match: %{content: "elixir"}}}

      assert {:ok, %{hits: hits, total: total}} = OpenSearch.search(@test_index, query)
      assert total >= 1
      assert length(hits) >= 1
      assert Enum.any?(hits, fn h -> h.id == "s1" end)
    end

    test "search/3 respects size option" do
      query = %{query: %{match_all: %{}}}

      assert {:ok, %{hits: hits}} = OpenSearch.search(@test_index, query, size: 1)
      assert length(hits) == 1
    end

    test "search/3 respects from option" do
      query = %{query: %{match_all: %{}}}

      assert {:ok, %{hits: hits}} = OpenSearch.search(@test_index, query, size: 10, from: 0)
      assert length(hits) == 3
    end

    test "search/3 returns empty results for no matches" do
      query = %{query: %{match: %{content: "nonexistent_xyz_term"}}}

      assert {:ok, %{hits: hits, total: total}} = OpenSearch.search(@test_index, query)
      assert total == 0
      assert hits == []
    end
  end
end
