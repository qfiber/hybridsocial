defmodule Hybridsocial.Search.Indexer do
  @moduledoc """
  Manages OpenSearch index creation, document indexing, and reindexing.
  """

  alias Hybridsocial.Search.OpenSearch
  alias Hybridsocial.Repo

  require Logger

  @posts_index "hybridsocial_posts"
  @accounts_index "hybridsocial_accounts"
  @hashtags_index "hybridsocial_hashtags"
  @groups_index "hybridsocial_groups"

  @batch_size 500

  # --- Index Setup ---

  @doc "Creates all required indexes with their mappings."
  def setup_indexes do
    with :ok <- setup_posts_index(),
         :ok <- setup_accounts_index(),
         :ok <- setup_hashtags_index(),
         :ok <- setup_groups_index() do
      Logger.info("OpenSearch indexes created successfully")
      :ok
    else
      {:error, reason} ->
        Logger.error("Failed to set up OpenSearch indexes: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp setup_posts_index do
    mapping = %{
      settings: %{number_of_replicas: 0},
      mappings: %{
        properties: %{
          content: %{type: "text", analyzer: "standard"},
          identity_id: %{type: "keyword"},
          handle: %{type: "keyword"},
          display_name: %{type: "text"},
          visibility: %{type: "keyword"},
          post_type: %{type: "keyword"},
          hashtags: %{type: "keyword"},
          language: %{type: "keyword"},
          reaction_count: %{type: "integer"},
          boost_count: %{type: "integer"},
          reply_count: %{type: "integer"},
          published_at: %{type: "date"},
          inserted_at: %{type: "date"}
        }
      }
    }

    OpenSearch.create_index(@posts_index, mapping)
  end

  defp setup_accounts_index do
    mapping = %{
      settings: %{number_of_replicas: 0},
      mappings: %{
        properties: %{
          handle: %{type: "text", fields: %{raw: %{type: "keyword"}}},
          display_name: %{type: "text"},
          bio: %{type: "text"},
          type: %{type: "keyword"},
          is_bot: %{type: "boolean"},
          followers_count: %{type: "integer"}
        }
      }
    }

    OpenSearch.create_index(@accounts_index, mapping)
  end

  defp setup_hashtags_index do
    mapping = %{
      settings: %{number_of_replicas: 0},
      mappings: %{
        properties: %{
          name: %{type: "text", fields: %{raw: %{type: "keyword"}}},
          usage_count: %{type: "integer"}
        }
      }
    }

    OpenSearch.create_index(@hashtags_index, mapping)
  end

  defp setup_groups_index do
    mapping = %{
      settings: %{number_of_replicas: 0},
      mappings: %{
        properties: %{
          name: %{type: "text", fields: %{raw: %{type: "keyword"}}},
          description: %{type: "text"},
          visibility: %{type: "keyword"},
          join_policy: %{type: "keyword"},
          member_count: %{type: "integer"},
          post_count: %{type: "integer"}
        }
      }
    }

    OpenSearch.create_index(@groups_index, mapping)
  end

  # --- Single Document Indexing ---

  @doc "Indexes a single post document."
  def index_post(post) do
    post = maybe_preload(post, :identity)

    doc = %{
      content: post.content,
      identity_id: post.identity_id,
      handle: get_in_struct(post, [:identity, :handle]),
      display_name: get_in_struct(post, [:identity, :display_name]),
      visibility: post.visibility,
      post_type: post.post_type,
      language: post.language,
      reaction_count: post.reaction_count || 0,
      boost_count: post.boost_count || 0,
      reply_count: post.reply_count || 0,
      published_at: format_datetime(post.published_at),
      inserted_at: format_datetime(post.inserted_at)
    }

    OpenSearch.index_document(@posts_index, post.id, doc)
  end

  @doc "Indexes a single identity document."
  def index_identity(identity) do
    doc = %{
      handle: identity.handle,
      display_name: identity.display_name,
      bio: identity.bio,
      type: identity.type,
      is_bot: identity.is_bot || false
    }

    OpenSearch.index_document(@accounts_index, identity.id, doc)
  end

  @doc "Indexes a single group document."
  def index_group(group) do
    doc = %{
      name: group.name,
      description: group.description,
      visibility: to_string(group.visibility),
      join_policy: to_string(group.join_policy),
      member_count: group.member_count || 0,
      post_count: group.post_count || 0
    }

    OpenSearch.index_document(@groups_index, group.id, doc)
  end

  @doc "Indexes a single hashtag document."
  def index_hashtag(hashtag) do
    doc = %{
      name: hashtag.name,
      usage_count: hashtag.usage_count || 0
    }

    OpenSearch.index_document(@hashtags_index, hashtag.id, doc)
  end

  # --- Document Removal ---

  @doc "Removes a post from the index."
  def remove_post(post_id) do
    OpenSearch.delete_document(@posts_index, post_id)
  end

  @doc "Removes an identity from the index."
  def remove_identity(identity_id) do
    OpenSearch.delete_document(@accounts_index, identity_id)
  end

  @doc "Removes a group from the index."
  def remove_group(group_id) do
    OpenSearch.delete_document(@groups_index, group_id)
  end

  # --- Full Reindexing ---

  @doc "Full reindex of all data from the database."
  def reindex_all do
    Logger.info("Starting full reindex...")

    with :ok <- reindex_posts(),
         :ok <- reindex_identities(),
         :ok <- reindex_hashtags(),
         :ok <- reindex_groups() do
      Logger.info("Full reindex completed")
      :ok
    else
      {:error, reason} ->
        Logger.error("Reindex failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc "Reindex all posts from the database."
  def reindex_posts do
    import Ecto.Query

    Logger.info("Reindexing posts...")

    Hybridsocial.Social.Post
    |> where([p], is_nil(p.deleted_at))
    |> Repo.all()
    |> Repo.preload(:identity)
    |> Enum.chunk_every(@batch_size)
    |> Enum.each(fn batch ->
      docs =
        Enum.map(batch, fn post ->
          %{
            id: post.id,
            content: post.content,
            identity_id: post.identity_id,
            handle: get_in_struct(post, [:identity, :handle]),
            display_name: get_in_struct(post, [:identity, :display_name]),
            visibility: post.visibility,
            post_type: post.post_type,
            language: post.language,
            reaction_count: post.reaction_count || 0,
            boost_count: post.boost_count || 0,
            reply_count: post.reply_count || 0,
            published_at: format_datetime(post.published_at),
            inserted_at: format_datetime(post.inserted_at)
          }
        end)

      case OpenSearch.bulk_index(@posts_index, docs) do
        :ok -> :ok
        {:error, reason} -> Logger.warning("Batch post indexing error: #{inspect(reason)}")
      end
    end)

    Logger.info("Posts reindexing completed")
    :ok
  end

  @doc "Reindex all identities from the database."
  def reindex_identities do
    import Ecto.Query

    Logger.info("Reindexing identities...")

    Hybridsocial.Accounts.Identity
    |> where([i], is_nil(i.deleted_at))
    |> where([i], i.is_suspended == false)
    |> Repo.all()
    |> Enum.chunk_every(@batch_size)
    |> Enum.each(fn batch ->
      docs =
        Enum.map(batch, fn identity ->
          %{
            id: identity.id,
            handle: identity.handle,
            display_name: identity.display_name,
            bio: identity.bio,
            type: identity.type,
            is_bot: identity.is_bot || false
          }
        end)

      case OpenSearch.bulk_index(@accounts_index, docs) do
        :ok -> :ok
        {:error, reason} -> Logger.warning("Batch identity indexing error: #{inspect(reason)}")
      end
    end)

    Logger.info("Identities reindexing completed")
    :ok
  end

  @doc "Reindex all hashtags from the database."
  def reindex_hashtags do
    Logger.info("Reindexing hashtags...")

    Hybridsocial.Social.Hashtag
    |> Repo.all()
    |> Enum.chunk_every(@batch_size)
    |> Enum.each(fn batch ->
      docs =
        Enum.map(batch, fn hashtag ->
          %{
            id: hashtag.id,
            name: hashtag.name,
            usage_count: hashtag.usage_count || 0
          }
        end)

      case OpenSearch.bulk_index(@hashtags_index, docs) do
        :ok -> :ok
        {:error, reason} -> Logger.warning("Batch hashtag indexing error: #{inspect(reason)}")
      end
    end)

    Logger.info("Hashtags reindexing completed")
    :ok
  end

  @doc "Reindex all groups from the database."
  def reindex_groups do
    import Ecto.Query

    Logger.info("Reindexing groups...")

    Hybridsocial.Groups.Group
    |> where([g], is_nil(g.deleted_at))
    |> Repo.all()
    |> Enum.chunk_every(@batch_size)
    |> Enum.each(fn batch ->
      docs =
        Enum.map(batch, fn group ->
          %{
            id: group.id,
            name: group.name,
            description: group.description,
            visibility: to_string(group.visibility),
            join_policy: to_string(group.join_policy),
            member_count: group.member_count || 0,
            post_count: group.post_count || 0
          }
        end)

      case OpenSearch.bulk_index(@groups_index, docs) do
        :ok -> :ok
        {:error, reason} -> Logger.warning("Batch group indexing error: #{inspect(reason)}")
      end
    end)

    Logger.info("Groups reindexing completed")
    :ok
  end

  # --- Helpers ---

  defp maybe_preload(%{identity: %Ecto.Association.NotLoaded{}} = struct, assoc) do
    Repo.preload(struct, assoc)
  end

  defp maybe_preload(struct, _assoc), do: struct

  defp get_in_struct(struct, [key | rest]) do
    case Map.get(struct, key) do
      nil -> nil
      %Ecto.Association.NotLoaded{} -> nil
      value when rest == [] -> value
      value -> get_in_struct(value, rest)
    end
  end

  defp format_datetime(nil), do: nil

  defp format_datetime(%DateTime{} = dt) do
    DateTime.to_iso8601(dt)
  end
end
