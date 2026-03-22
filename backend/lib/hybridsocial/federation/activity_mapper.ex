defmodule Hybridsocial.Federation.ActivityMapper do
  @moduledoc """
  Maps ActivityPub objects to internal model attributes.
  """

  @emoji_map %{
    "❤️" => "love",
    "❤" => "love",
    "😂" => "lol",
    "🤣" => "lol",
    "😢" => "sad",
    "😭" => "sad",
    "😡" => "angry",
    "😠" => "angry",
    "🤗" => "care",
    "😱" => "wtf",
    "😲" => "wtf",
    "👍" => "like",
    "⭐" => "like"
  }

  @doc """
  Converts a Note/Article AP object to internal post attributes.
  """
  def to_post(ap_object) when is_map(ap_object) do
    visibility = determine_visibility(ap_object)
    post_type = determine_post_type(ap_object)

    attrs = %{
      "ap_id" => ap_object["id"],
      "content" => ap_object["content"],
      "content_html" => ap_object["content"],
      "post_type" => post_type,
      "visibility" => visibility,
      "sensitive" => ap_object["sensitive"] || false,
      "spoiler_text" => ap_object["summary"],
      "language" => extract_language(ap_object),
      "published_at" => parse_datetime(ap_object["published"])
    }

    attrs
    |> maybe_put("parent_ap_id", ap_object["inReplyTo"])
    |> Map.reject(fn {_k, v} -> is_nil(v) end)
  end

  @doc """
  Converts an AP Actor to remote_actor attributes.
  """
  def to_actor(ap_actor) when is_map(ap_actor) do
    domain = extract_domain(ap_actor["id"])

    %{
      ap_id: ap_actor["id"],
      handle: ap_actor["preferredUsername"],
      domain: domain,
      display_name: ap_actor["name"],
      avatar_url: extract_icon_url(ap_actor["icon"]),
      public_key: extract_public_key(ap_actor),
      inbox_url: ap_actor["inbox"],
      outbox_url: ap_actor["outbox"],
      followers_url: ap_actor["followers"],
      shared_inbox_url: get_in(ap_actor, ["endpoints", "sharedInbox"])
    }
  end

  @doc """
  Maps an emoji or content string to a reaction type.
  Falls back to :like for unknown emoji.
  """
  def to_reaction_type(nil), do: "like"
  def to_reaction_type(""), do: "like"

  def to_reaction_type(content) when is_binary(content) do
    # Try direct match first, then try first grapheme
    case Map.get(@emoji_map, content) do
      nil ->
        grapheme = String.graphemes(content) |> List.first()
        Map.get(@emoji_map, grapheme, "like")

      type ->
        type
    end
  end

  @doc """
  Extracts the domain from an AP ID URL.
  """
  def extract_domain(nil), do: nil

  def extract_domain(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) -> host
      _ -> nil
    end
  end

  # Private helpers

  defp determine_visibility(ap_object) do
    to = List.wrap(ap_object["to"])
    cc = List.wrap(ap_object["cc"])
    all_recipients = to ++ cc

    public = "https://www.w3.org/ns/activitystreams#Public"

    cond do
      public in to -> "public"
      public in cc -> "public"
      has_followers_address?(all_recipients) -> "followers"
      true -> "direct"
    end
  end

  defp has_followers_address?(recipients) do
    Enum.any?(recipients, fn r ->
      is_binary(r) and String.ends_with?(r, "/followers")
    end)
  end

  defp determine_post_type(ap_object) do
    case ap_object["type"] do
      "Article" -> "article"
      _ -> "text"
    end
  end

  defp extract_language(ap_object) do
    case ap_object["contentMap"] do
      map when is_map(map) ->
        map |> Map.keys() |> List.first()

      _ ->
        nil
    end
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} ->
        # Ensure microsecond precision for Ecto's utc_datetime_usec
        %{dt | microsecond: {elem(dt.microsecond, 0), 6}}

      _ ->
        nil
    end
  end

  defp extract_icon_url(%{"url" => url}) when is_binary(url), do: url
  defp extract_icon_url(_), do: nil

  defp extract_public_key(ap_actor) do
    case ap_actor["publicKey"] do
      %{"publicKeyPem" => pem} when is_binary(pem) -> pem
      _ -> nil
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
