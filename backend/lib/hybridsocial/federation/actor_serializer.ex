defmodule Hybridsocial.Federation.ActorSerializer do
  @moduledoc """
  Serializes local identities to ActivityPub Actor objects.
  """

  alias Hybridsocial.Accounts.Identity

  @ap_context [
    "https://www.w3.org/ns/activitystreams",
    "https://w3id.org/security/v1"
  ]

  @doc """
  Returns the full AP Actor JSON-LD object for a local identity.
  """
  def to_ap(identity) do
    base_url = HybridsocialWeb.Endpoint.url()

    # Prefer the stored ActivityPub URLs so actors imported from a retired
    # instance keep their original `id`, collections, and keyId. For
    # natively-created identities the stored values are exactly the
    # computed `/actors/<uuid>` forms, so this is byte-identical to what
    # we served before.
    computed = "#{base_url}/actors/#{identity.id}"
    actor_url = identity.ap_actor_url || computed

    actor = %{
      "@context" => @ap_context,
      "id" => actor_url,
      "type" => actor_type(identity.type),
      "preferredUsername" => identity.handle,
      "name" => identity.display_name || identity.handle,
      "summary" => identity.bio || "",
      "manuallyApprovesFollowers" => identity.is_locked || false,
      "discoverable" => Map.get(identity, :discoverable, true),
      "inbox" => identity.inbox_url || "#{actor_url}/inbox",
      "outbox" => identity.outbox_url || "#{actor_url}/outbox",
      "followers" => identity.followers_url || "#{actor_url}/followers",
      "following" => identity.following_url || "#{actor_url}/following",
      "featured" => identity.featured_url || "#{actor_url}/collections/featured",
      "url" => actor_url,
      "publicKey" => %{
        "id" => "#{actor_url}#main-key",
        "owner" => actor_url,
        "publicKeyPem" => identity.public_key
      },
      "attachment" => build_profile_fields(identity),
      "tag" => build_actor_emoji_tags(identity),
      "endpoints" => %{
        "sharedInbox" => identity.shared_inbox_url || "#{base_url}/inbox"
      }
    }

    actor
    |> maybe_add_icon(identity)
    |> maybe_add_image(identity)
    |> maybe_add_moved_to(identity)
    |> maybe_add_also_known_as(identity)
  end

  defp actor_type("organization"), do: "Organization"
  defp actor_type("bot"), do: "Service"
  defp actor_type("group"), do: "Group"
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

  # Only the profile fields a user wrote, never the rest of `metadata`. Receiving
  # servers treat `value` as HTML, so escape it: this is plain text.
  defp build_profile_fields(identity) do
    identity
    |> Identity.profile_fields()
    |> Enum.map(fn %{"name" => name, "value" => value} ->
      %{
        "type" => "PropertyValue",
        "name" => name,
        "value" => value |> Plug.HTML.html_escape() |> to_string()
      }
    end)
    |> Enum.take(5)
  end

  defp build_actor_emoji_tags(identity) do
    text = "#{identity.display_name || ""} #{identity.bio || ""}"

    Regex.scan(~r/:([a-zA-Z0-9_]+):/, text)
    |> Enum.map(fn [_, shortcode] ->
      case Hybridsocial.Content.Emojis.get_emoji_by_shortcode(shortcode) do
        nil ->
          nil

        emoji ->
          %{
            "type" => "Emoji",
            "id" => emoji.image_url,
            "name" => ":#{emoji.shortcode}:",
            "icon" => %{
              "type" => "Image",
              "url" => emoji.image_url
            }
          }
      end
    end)
    |> Enum.reject(&is_nil/1)
  end
end
