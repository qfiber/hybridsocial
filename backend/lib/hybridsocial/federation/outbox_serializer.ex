defmodule Hybridsocial.Federation.OutboxSerializer do
  @moduledoc """
  Serializes an identity's outbox as an ActivityPub OrderedCollection.
  """

  import Ecto.Query
  alias Hybridsocial.Repo
  alias Hybridsocial.Social.Post
  alias Hybridsocial.Federation.ActivityBuilder

  @default_page_size 20

  @doc """
  Serializes the outbox for an identity.

  When `page` is nil, returns the OrderedCollection summary.
  When `page` is an integer, returns the OrderedCollectionPage with activities.

  Options:
    - `:page_size` - number of items per page (default: 20)
  """
  def serialize_outbox(identity, page \\ nil, opts \\ []) do
    if page do
      serialize_page(identity, page, opts)
    else
      serialize_collection(identity)
    end
  end

  # --- Private ---

  defp serialize_collection(identity) do
    total = count_posts(identity.id)
    outbox_url = "#{base_url()}/actors/#{identity.id}/outbox"

    %{
      "@context" => "https://www.w3.org/ns/activitystreams",
      "id" => outbox_url,
      "type" => "OrderedCollection",
      "totalItems" => total,
      "first" => "#{outbox_url}?page=1",
      "last" => "#{outbox_url}?page=#{max(1, ceil_div(total, @default_page_size))}"
    }
  end

  defp serialize_page(identity, page, opts) do
    page_size = Keyword.get(opts, :page_size, @default_page_size)
    page = max(1, page)
    offset = (page - 1) * page_size

    posts =
      Post
      |> where([p], p.identity_id == ^identity.id)
      |> where([p], is_nil(p.deleted_at))
      |> where([p], p.visibility == "public")
      |> order_by([p], desc: p.published_at)
      |> limit(^page_size)
      |> offset(^offset)
      |> Repo.all()
      |> Repo.preload(:identity)

    total = count_posts(identity.id)
    total_pages = max(1, ceil_div(total, page_size))
    outbox_url = "#{base_url()}/actors/#{identity.id}/outbox"

    activities = Enum.map(posts, &ActivityBuilder.build_create/1)

    result = %{
      "@context" => "https://www.w3.org/ns/activitystreams",
      "id" => "#{outbox_url}?page=#{page}",
      "type" => "OrderedCollectionPage",
      "partOf" => outbox_url,
      "totalItems" => total,
      "orderedItems" => activities
    }

    result =
      if page > 1 do
        Map.put(result, "prev", "#{outbox_url}?page=#{page - 1}")
      else
        result
      end

    if page < total_pages do
      Map.put(result, "next", "#{outbox_url}?page=#{page + 1}")
    else
      result
    end
  end

  defp count_posts(identity_id) do
    Post
    |> where([p], p.identity_id == ^identity_id)
    |> where([p], is_nil(p.deleted_at))
    |> where([p], p.visibility == "public")
    |> Repo.aggregate(:count)
  end

  defp ceil_div(_num, 0), do: 1
  defp ceil_div(num, den), do: div(num + den - 1, den)

  defp base_url do
    HybridsocialWeb.Endpoint.url()
  end
end
