defmodule HybridsocialWeb.Federation.ActorController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Accounts
  alias Hybridsocial.Federation.ActorSerializer

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

        collection = %{
          "@context" => "https://www.w3.org/ns/activitystreams",
          "id" => collection_url,
          "type" => "OrderedCollection",
          "totalItems" => 0,
          "orderedItems" => []
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

        collection = %{
          "@context" => "https://www.w3.org/ns/activitystreams",
          "id" => collection_url,
          "type" => "OrderedCollection",
          "totalItems" => 0,
          "orderedItems" => []
        }

        conn
        |> put_resp_content_type(@ap_content_type)
        |> json(collection)
    end
  end

  def outbox(conn, %{"id" => id}) do
    case Accounts.get_identity(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Actor not found"})

      identity ->
        base_url = HybridsocialWeb.Endpoint.url()
        collection_url = "#{base_url}/actors/#{identity.id}/outbox"

        collection = %{
          "@context" => "https://www.w3.org/ns/activitystreams",
          "id" => collection_url,
          "type" => "OrderedCollection",
          "totalItems" => 0,
          "orderedItems" => []
        }

        conn
        |> put_resp_content_type(@ap_content_type)
        |> json(collection)
    end
  end
end
