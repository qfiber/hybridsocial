defmodule HybridsocialWeb.Federation.ActorController do
  use HybridsocialWeb, :controller

  import Ecto.Query

  alias Hybridsocial.Repo
  alias Hybridsocial.Accounts
  alias Hybridsocial.Accounts.Identity
  alias Hybridsocial.Social.Follow
  alias Hybridsocial.Federation.ActorSerializer
  alias Hybridsocial.Federation.OutboxSerializer

  @ap_content_type "application/activity+json"

  def show(conn, %{"id" => id}) do
    case Accounts.get_identity(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Actor not found"})

      identity ->
        actor = ActorSerializer.to_ap(identity)

        conn
        |> put_resp_content_type(@ap_content_type)
        |> json(actor)
    end
  end

  def followers(conn, %{"id" => id}) do
    case Accounts.get_identity(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Actor not found"})

      identity ->
        base_url = HybridsocialWeb.Endpoint.url()
        collection_url = "#{base_url}/actors/#{identity.id}/followers"

        follower_identities =
          Follow
          |> where([f], f.followee_id == ^identity.id and f.status == :accepted)
          |> join(:inner, [f], i in Identity, on: f.follower_id == i.id)
          |> select([f, i], i)
          |> Repo.all()

        follower_urls =
          Enum.map(follower_identities, fn i ->
            if i.ap_actor_url && !String.starts_with?(i.ap_actor_url, base_url) do
              i.ap_actor_url
            else
              "#{base_url}/actors/#{i.id}"
            end
          end)

        collection = %{
          "@context" => "https://www.w3.org/ns/activitystreams",
          "id" => collection_url,
          "type" => "OrderedCollection",
          "totalItems" => length(follower_urls),
          "orderedItems" => follower_urls
        }

        conn
        |> put_resp_content_type(@ap_content_type)
        |> json(collection)
    end
  end

  def following(conn, %{"id" => id}) do
    case Accounts.get_identity(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Actor not found"})

      identity ->
        base_url = HybridsocialWeb.Endpoint.url()
        collection_url = "#{base_url}/actors/#{identity.id}/following"

        following_identities =
          Follow
          |> where([f], f.follower_id == ^identity.id and f.status == :accepted)
          |> join(:inner, [f], i in Identity, on: f.followee_id == i.id)
          |> select([f, i], i)
          |> Repo.all()

        following_urls =
          Enum.map(following_identities, fn i ->
            if i.ap_actor_url && !String.starts_with?(i.ap_actor_url, base_url) do
              i.ap_actor_url
            else
              "#{base_url}/actors/#{i.id}"
            end
          end)

        collection = %{
          "@context" => "https://www.w3.org/ns/activitystreams",
          "id" => collection_url,
          "type" => "OrderedCollection",
          "totalItems" => length(following_urls),
          "orderedItems" => following_urls
        }

        conn
        |> put_resp_content_type(@ap_content_type)
        |> json(collection)
    end
  end

  def featured(conn, %{"id" => id}) do
    base_url = HybridsocialWeb.Endpoint.url()

    # Get pinned posts for this actor
    pinned =
      from(p in "posts",
        where: p.identity_id == ^id and p.is_pinned == true and is_nil(p.deleted_at),
        select: p.id,
        order_by: [desc: p.inserted_at]
      )
      |> Repo.all()

    items = Enum.map(pinned, fn post_id -> "#{base_url}/posts/#{post_id}" end)

    conn
    |> put_resp_content_type(@ap_content_type)
    |> json(%{
      "@context" => "https://www.w3.org/ns/activitystreams",
      "id" => "#{base_url}/actors/#{id}/collections/featured",
      "type" => "OrderedCollection",
      "totalItems" => length(items),
      "orderedItems" => items
    })
  end

  def outbox(conn, %{"id" => id} = params) do
    case Accounts.get_identity(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Actor not found"})

      identity ->
        page =
          case params["page"] do
            nil -> nil
            p when is_binary(p) -> String.to_integer(p)
            p when is_integer(p) -> p
          end

        collection = OutboxSerializer.serialize_outbox(identity, page)

        conn
        |> put_resp_content_type(@ap_content_type)
        |> json(collection)
    end
  end
end
