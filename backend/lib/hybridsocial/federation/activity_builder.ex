defmodule Hybridsocial.Federation.ActivityBuilder do
  @moduledoc """
  Builds ActivityPub activity objects from internal data structures.
  """

  @public "https://www.w3.org/ns/activitystreams#Public"
  @context "https://www.w3.org/ns/activitystreams"

  # --- Create ---

  def build_create(post) do
    post = maybe_preload(post, :identity)
    actor_url = actor_url(post.identity)
    note = build_note(post)

    %{
      "@context" => @context,
      "id" => activity_id(post.identity.id, "create", post.id),
      "type" => "Create",
      "actor" => actor_url,
      "published" => format_datetime(post.published_at || post.inserted_at),
      "to" => note["to"],
      "cc" => note["cc"],
      "object" => note
    }
  end

  # --- Update ---

  def build_update(post) do
    post = maybe_preload(post, :identity)
    actor_url = actor_url(post.identity)
    note = build_note(post)

    %{
      "@context" => @context,
      "id" => activity_id(post.identity.id, "update", post.id),
      "type" => "Update",
      "actor" => actor_url,
      "published" => format_datetime(post.edited_at || DateTime.utc_now()),
      "to" => note["to"],
      "cc" => note["cc"],
      "object" => note
    }
  end

  # --- Delete ---

  def build_delete(post) do
    post = maybe_preload(post, :identity)
    actor_url = actor_url(post.identity)

    %{
      "@context" => @context,
      "id" => activity_id(post.identity.id, "delete", post.id),
      "type" => "Delete",
      "actor" => actor_url,
      "published" => format_datetime(DateTime.utc_now()),
      "to" => [@public],
      "cc" => [followers_url(post.identity)],
      "object" => %{
        "id" => post_url(post.id),
        "type" => "Tombstone"
      }
    }
  end

  # --- Follow ---

  def build_follow(follower_identity, followee_ap_id) do
    actor_url = actor_url(follower_identity)
    target_uuid = extract_uuid_from_url(followee_ap_id)

    %{
      "@context" => @context,
      "id" => activity_id(follower_identity.id, "follow", target_uuid),
      "type" => "Follow",
      "actor" => actor_url,
      "object" => followee_ap_id
    }
  end

  # --- Accept Follow ---

  def build_accept_follow(identity, follow_activity_id) do
    actor_url = actor_url(identity)
    target_uuid = extract_uuid_from_url(follow_activity_id)

    %{
      "@context" => @context,
      "id" => activity_id(identity.id, "accept", target_uuid),
      "type" => "Accept",
      "actor" => actor_url,
      "object" => follow_activity_id
    }
  end

  # --- Reject Follow ---

  def build_reject_follow(identity, follow_activity_id) do
    actor_url = actor_url(identity)
    target_uuid = extract_uuid_from_url(follow_activity_id)

    %{
      "@context" => @context,
      "id" => activity_id(identity.id, "reject", target_uuid),
      "type" => "Reject",
      "actor" => actor_url,
      "object" => follow_activity_id
    }
  end

  # --- Like ---

  def build_like(identity, post) do
    actor_url = actor_url(identity)

    %{
      "@context" => @context,
      "id" => activity_id(identity.id, "like", post.id),
      "type" => "Like",
      "actor" => actor_url,
      "object" => post_url(post.id)
    }
  end

  # --- Announce (Boost) ---

  def build_announce(identity, post) do
    actor_url = actor_url(identity)

    %{
      "@context" => @context,
      "id" => activity_id(identity.id, "announce", post.id),
      "type" => "Announce",
      "actor" => actor_url,
      "published" => format_datetime(DateTime.utc_now()),
      "to" => [@public],
      "cc" => [followers_url(identity), actor_url(post.identity)],
      "object" => post_url(post.id)
    }
  end

  # --- Undo ---

  def build_undo(identity, activity_to_undo) do
    actor_url = actor_url(identity)
    target_uuid = extract_uuid_from_url(activity_to_undo["id"])

    %{
      "@context" => @context,
      "id" => activity_id(identity.id, "undo", target_uuid),
      "type" => "Undo",
      "actor" => actor_url,
      "object" => activity_to_undo
    }
  end

  # --- Block ---

  def build_block(identity, target_ap_id) do
    actor_url = actor_url(identity)
    target_uuid = extract_uuid_from_url(target_ap_id)

    %{
      "@context" => @context,
      "id" => activity_id(identity.id, "block", target_uuid),
      "type" => "Block",
      "actor" => actor_url,
      "object" => target_ap_id
    }
  end

  # --- Move ---

  def build_move(old_identity, new_ap_id) do
    actor_url = actor_url(old_identity)
    target_uuid = extract_uuid_from_url(new_ap_id)

    %{
      "@context" => @context,
      "id" => activity_id(old_identity.id, "move", target_uuid),
      "type" => "Move",
      "actor" => actor_url,
      "object" => actor_url,
      "target" => new_ap_id
    }
  end

  # --- Note builder ---

  defp build_note(post) do
    {to, cc} = determine_addressing(post)

    note = %{
      "@context" => @context,
      "id" => post_url(post.id),
      "type" => "Note",
      "attributedTo" => actor_url(post.identity),
      "content" => post.content_html || post.content,
      "published" => format_datetime(post.published_at || post.inserted_at),
      "to" => to,
      "cc" => cc,
      "inReplyTo" => build_in_reply_to(post),
      "sensitive" => post.sensitive || false,
      "summary" => post.spoiler_text,
      "tag" => build_tags(post),
      "url" => post_url(post.id)
    }

    if post.edited_at do
      Map.put(note, "updated", format_datetime(post.edited_at))
    else
      note
    end
  end

  defp determine_addressing(post) do
    followers = followers_url(post.identity)

    case post.visibility do
      "public" -> {[@public], [followers]}
      "followers" -> {[followers], []}
      "direct" -> {[], []}
      _ -> {[@public], [followers]}
    end
  end

  defp build_in_reply_to(%{parent_id: nil}), do: nil

  defp build_in_reply_to(%{parent_id: parent_id}) when not is_nil(parent_id) do
    post_url(parent_id)
  end

  defp build_in_reply_to(_), do: nil

  defp build_tags(post) do
    if post.content do
      ~r/#([a-zA-Z0-9_]+)/
      |> Regex.scan(post.content)
      |> Enum.map(fn [_, tag] ->
        %{
          "type" => "Hashtag",
          "href" => "#{base_url()}/tags/#{String.downcase(tag)}",
          "name" => "##{String.downcase(tag)}"
        }
      end)
    else
      []
    end
  end

  # --- URL helpers ---

  defp activity_id(actor_uuid, action, target_uuid) do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    "#{base_url()}/activities/#{actor_uuid}/#{action}/#{target_uuid}/#{timestamp}"
  end

  defp actor_url(identity) do
    "#{base_url()}/actors/#{identity.id}"
  end

  defp post_url(post_id) do
    "#{base_url()}/posts/#{post_id}"
  end

  defp followers_url(identity) do
    "#{base_url()}/actors/#{identity.id}/followers"
  end

  defp base_url do
    HybridsocialWeb.Endpoint.url()
  end

  defp format_datetime(nil), do: nil

  defp format_datetime(%DateTime{} = dt) do
    DateTime.to_iso8601(dt)
  end

  defp extract_uuid_from_url(nil), do: "unknown"

  defp extract_uuid_from_url(url) when is_binary(url) do
    # Try to extract a UUID from the URL, fall back to a hash of the URL
    case Regex.run(~r/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/i, url) do
      [_, uuid] -> uuid
      nil -> :crypto.hash(:sha256, url) |> Base.url_encode64(padding: false) |> binary_part(0, 16)
    end
  end

  defp maybe_preload(%{identity: %Hybridsocial.Accounts.Identity{}} = post, :identity), do: post

  defp maybe_preload(post, :identity) do
    Hybridsocial.Repo.preload(post, :identity)
  end
end
