defmodule Hybridsocial.Federation.ActorSerializer do
  @moduledoc """
  Serializes local identities to ActivityPub Actor objects.
  """

  @ap_context [
    "https://www.w3.org/ns/activitystreams",
    "https://w3id.org/security/v1"
  ]

  @doc """
  Returns the full AP Actor JSON-LD object for a local identity.
  """
  def to_ap(identity) do
    base_url = HybridsocialWeb.Endpoint.url()
    actor_url = "#{base_url}/actors/#{identity.id}"

    actor = %{
      "@context" => @ap_context,
      "id" => actor_url,
      "type" => actor_type(identity.type),
      "preferredUsername" => identity.handle,
      "name" => identity.display_name || identity.handle,
      "summary" => identity.bio || "",
      "manuallyApprovesFollowers" => identity.is_locked || false,
      "discoverable" => true,
      "inbox" => "#{actor_url}/inbox",
      "outbox" => "#{actor_url}/outbox",
      "followers" => "#{actor_url}/followers",
      "following" => "#{actor_url}/following",
      "url" => actor_url,
      "publicKey" => %{
        "id" => "#{actor_url}#main-key",
        "owner" => actor_url,
        "publicKeyPem" => identity.public_key
      },
      "endpoints" => %{
        "sharedInbox" => "#{base_url}/inbox"
      }
    }

    actor
    |> maybe_add_icon(identity)
    |> maybe_add_image(identity)
    |> maybe_add_moved_to(identity)
    |> maybe_add_also_known_as(identity)
  end

  defp actor_type("organization"), do: "Organization"
  defp actor_type(_), do: "Person"

  defp maybe_add_icon(actor, %{avatar_url: nil}), do: actor

  defp maybe_add_icon(actor, %{avatar_url: url}) do
    Map.put(actor, "icon", %{
      "type" => "Image",
      "url" => url
    })
  end

  defp maybe_add_image(actor, %{header_url: nil}), do: actor

  defp maybe_add_image(actor, %{header_url: url}) do
    Map.put(actor, "image", %{
      "type" => "Image",
      "url" => url
    })
  end

  defp maybe_add_moved_to(actor, %{moved_to: nil}), do: actor
  defp maybe_add_moved_to(actor, %{moved_to: ""}), do: actor

  defp maybe_add_moved_to(actor, %{moved_to: moved_to}) do
    Map.put(actor, "movedTo", moved_to)
  end

  defp maybe_add_moved_to(actor, _), do: actor

  defp maybe_add_also_known_as(actor, %{also_known_as: aka}) when is_list(aka) and aka != [] do
    Map.put(actor, "alsoKnownAs", aka)
  end

  defp maybe_add_also_known_as(actor, _), do: actor
end
