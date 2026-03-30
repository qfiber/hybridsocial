defmodule HybridsocialWeb.Serializers.PostSerializer do
  @moduledoc """
  Shared post serialization for API responses.
  Enriches posts with user-specific state, reactions breakdown,
  link previews, mentions, tags, and custom emoji.
  """

  import Ecto.Query

  alias Hybridsocial.Repo
  alias Hybridsocial.Social.{Reaction, Boost, Bookmark, PostMute}
  alias Hybridsocial.Content.{LinkPreviews, CustomEmoji}

  @doc """
  Serializes a single post. Pass current_identity_id to include
  user-specific state (boosted, bookmarked, muted, current_reaction).
  """
  def serialize(post, opts \\ [])

  def serialize(%{deleted_at: deleted_at} = post, _opts) when not is_nil(deleted_at) do
    serialize_tombstone(post.id)
  end

  def serialize(post, opts) do
    current_identity_id = Keyword.get(opts, :current_identity_id)

    badges =
      Hybridsocial.Badges.badges_for_post(
        post.identity,
        group_id: post.group_id,
        page_id: post.page_id
      )

    account = serialize_account(post.identity, badges)

    quote_post =
      case post.quote do
        %Hybridsocial.Social.Post{} = q ->
          q = Repo.preload(q, :identity)
          serialize(q, opts)

        _ ->
          nil
      end

    sensitive =
      case post.identity do
        %{force_sensitive: true} -> true
        _ -> post.sensitive
      end

    # User-specific state
    {is_boosted, is_bookmarked, is_muted, current_reaction} =
      if current_identity_id do
        user_state_for(post.id, current_identity_id)
      else
        {false, false, false, nil}
      end

    # Reactions breakdown
    reactions = reactions_for(post.id, current_identity_id)

    # Link preview
    card = card_for(post)

    # Mentions extracted from content
    mentions = extract_mentions(post.content_html || post.content || "")

    # Hashtags linked to this post
    tags = tags_for(post.id)

    # Custom emoji used in content
    emojis = emojis_in_content(post.content || "")

    # In reply to account
    in_reply_to_account_id = in_reply_to_account_id(post)

    # URIs
    base_url = HybridsocialWeb.Endpoint.url()

    %{
      id: post.id,
      type: post.post_type,
      uri: post.ap_id || "#{base_url}/posts/#{post.id}",
      url: "#{base_url}/post/#{post.id}",
      content: post.content,
      content_html: post.content_html,
      visibility: post.visibility,
      sensitive: sensitive,
      spoiler_text: post.spoiler_text,
      language: post.language,
      reply_count: post.reply_count,
      boost_count: post.boost_count,
      reaction_count: post.reaction_count,
      is_pinned: post.is_pinned,
      is_boosted: is_boosted,
      is_bookmarked: is_bookmarked,
      is_muted: is_muted,
      current_user_reaction: current_reaction,
      created_at: post.inserted_at,
      edited_at: post.edited_at,
      edit_expires_at: Map.get(post, :edit_expires_at),
      account: account,
      parent_id: post.parent_id,
      root_id: post.root_id,
      in_reply_to_account_id: in_reply_to_account_id,
      quote: quote_post,
      card: card,
      mentions: mentions,
      tags: tags,
      emojis: emojis,
      reactions: reactions
    }
  end

  @doc """
  Serializes a list of posts, batch-loading user state for efficiency.
  """
  def serialize_many(posts, opts \\ []) do
    current_identity_id = Keyword.get(opts, :current_identity_id)
    post_ids = Enum.map(posts, & &1.id)

    # Batch load user state
    {boosts_set, bookmarks_set, mutes_set, reactions_map} =
      if current_identity_id do
        batch_user_state(post_ids, current_identity_id)
      else
        {MapSet.new(), MapSet.new(), MapSet.new(), %{}}
      end

    # Batch load reactions breakdown
    reactions_breakdown = batch_reactions(post_ids, current_identity_id)

    Enum.map(posts, fn post ->
      badges =
        Hybridsocial.Badges.badges_for_post(
          post.identity,
          group_id: post.group_id,
          page_id: post.page_id
        )

      account = serialize_account(post.identity, badges)

      quote_post =
        case post.quote do
          %Hybridsocial.Social.Post{} = q ->
            q = Repo.preload(q, :identity)
            serialize(q, opts)
          _ ->
            nil
        end

      sensitive =
        case post.identity do
          %{force_sensitive: true} -> true
          _ -> post.sensitive
        end

      card = card_for(post)
      mentions = extract_mentions(post.content_html || post.content || "")
      tags = tags_for(post.id)
      emojis = emojis_in_content(post.content || "")
      in_reply_to_account_id = in_reply_to_account_id(post)

      base_url = HybridsocialWeb.Endpoint.url()

      %{
        id: post.id,
        type: post.post_type,
        uri: post.ap_id || "#{base_url}/posts/#{post.id}",
        url: "#{base_url}/post/#{post.id}",
        content: post.content,
        content_html: post.content_html,
        visibility: post.visibility,
        sensitive: sensitive,
        spoiler_text: post.spoiler_text,
        language: post.language,
        reply_count: post.reply_count,
        boost_count: post.boost_count,
        reaction_count: post.reaction_count,
        is_pinned: post.is_pinned,
        is_boosted: MapSet.member?(boosts_set, post.id),
        is_bookmarked: MapSet.member?(bookmarks_set, post.id),
        is_muted: MapSet.member?(mutes_set, post.id),
        current_user_reaction: Map.get(reactions_map, post.id),
        created_at: post.inserted_at,
        edited_at: post.edited_at,
      edit_expires_at: Map.get(post, :edit_expires_at),
        account: account,
        parent_id: post.parent_id,
        root_id: post.root_id,
        in_reply_to_account_id: in_reply_to_account_id,
        quote: quote_post,
        card: card,
        mentions: mentions,
        tags: tags,
        emojis: emojis,
        reactions: Map.get(reactions_breakdown, post.id, [])
      }
    end)
  end

  @doc "Serialize a tombstone placeholder for unavailable posts."
  def serialize_tombstone(id) do
    %{
      id: id,
      type: "tombstone",
      content: nil,
      content_html: nil,
      tombstone: %{reason: "deleted"}
    }
  end

  # --- Account ---

  def serialize_account(nil, _badges), do: nil

  def serialize_account(%Hybridsocial.Accounts.Identity{} = identity, badges) do
    domain = extract_domain(identity)

    %{
      id: identity.id,
      handle: identity.handle,
      acct: HybridsocialWeb.Helpers.Account.build_acct(identity),
      display_name: identity.display_name,
      avatar_url: identity.avatar_url,
      header_url: Map.get(identity, :header_url, nil),
      bio: Map.get(identity, :bio, nil),
      is_bot: Map.get(identity, :is_bot, false),
      is_locked: Map.get(identity, :is_locked, false),
      badges: badges,
      domain: domain,
      url: Map.get(identity, :url, nil),
      created_at: identity.inserted_at
    }
  end

  def serialize_account(_, _), do: nil

  # --- Private helpers ---

  defp user_state_for(post_id, identity_id) do
    is_boosted =
      Boost
      |> where([b], b.post_id == ^post_id and b.identity_id == ^identity_id and is_nil(b.deleted_at))
      |> Repo.exists?()

    is_bookmarked =
      Bookmark
      |> where([b], b.post_id == ^post_id and b.identity_id == ^identity_id)
      |> Repo.exists?()

    is_muted =
      PostMute
      |> where([m], m.post_id == ^post_id and m.identity_id == ^identity_id)
      |> Repo.exists?()

    current_reaction =
      Reaction
      |> where([r], r.post_id == ^post_id and r.identity_id == ^identity_id)
      |> select([r], r.type)
      |> Repo.one()

    {is_boosted, is_bookmarked, is_muted, current_reaction}
  end

  defp batch_user_state(post_ids, identity_id) when post_ids != [] do
    boosts =
      Boost
      |> where([b], b.post_id in ^post_ids and b.identity_id == ^identity_id and is_nil(b.deleted_at))
      |> select([b], b.post_id)
      |> Repo.all()
      |> MapSet.new()

    bookmarks =
      Bookmark
      |> where([b], b.post_id in ^post_ids and b.identity_id == ^identity_id)
      |> select([b], b.post_id)
      |> Repo.all()
      |> MapSet.new()

    mutes =
      PostMute
      |> where([m], m.post_id in ^post_ids and m.identity_id == ^identity_id)
      |> select([m], m.post_id)
      |> Repo.all()
      |> MapSet.new()

    reactions =
      Reaction
      |> where([r], r.post_id in ^post_ids and r.identity_id == ^identity_id)
      |> select([r], {r.post_id, r.type})
      |> Repo.all()
      |> Map.new()

    {boosts, bookmarks, mutes, reactions}
  end

  defp batch_user_state(_, _), do: {MapSet.new(), MapSet.new(), MapSet.new(), %{}}

  defp reactions_for(post_id, current_identity_id) do
    rows =
      Reaction
      |> where([r], r.post_id == ^post_id)
      |> group_by([r], r.type)
      |> select([r], {r.type, count(r.id)})
      |> Repo.all()

    Enum.map(rows, fn {type, count} ->
      me =
        if current_identity_id do
          Reaction
          |> where([r], r.post_id == ^post_id and r.type == ^type and r.identity_id == ^current_identity_id)
          |> Repo.exists?()
        else
          false
        end

      %{name: type, count: count, me: me}
    end)
  end

  defp batch_reactions(post_ids, current_identity_id) when post_ids != [] do
    # Group reactions by post_id and type
    rows =
      Reaction
      |> where([r], r.post_id in ^post_ids)
      |> group_by([r], [r.post_id, r.type])
      |> select([r], {r.post_id, r.type, count(r.id)})
      |> Repo.all()

    # Get current user's reactions
    my_reactions =
      if current_identity_id do
        Reaction
        |> where([r], r.post_id in ^post_ids and r.identity_id == ^current_identity_id)
        |> select([r], {r.post_id, r.type})
        |> Repo.all()
        |> MapSet.new()
      else
        MapSet.new()
      end

    rows
    |> Enum.group_by(fn {post_id, _type, _count} -> post_id end)
    |> Map.new(fn {post_id, entries} ->
      reactions =
        Enum.map(entries, fn {_pid, type, count} ->
          %{name: type, count: count, me: MapSet.member?(my_reactions, {post_id, type})}
        end)

      {post_id, reactions}
    end)
  end

  defp batch_reactions(_, _), do: %{}

  defp card_for(post) do
    case LinkPreviews.preview_for_post(post) do
      {:ok, preview} ->
        %{
          url: preview.url,
          title: preview.title,
          description: preview.description,
          image: preview.image_url,
          provider_name: preview.site_name
        }

      _ ->
        nil
    end
  end

  defp extract_mentions(html) when is_binary(html) do
    # Extract @mentions from content — look for links with class="mention" or @handle patterns
    mention_regex = ~r/@([a-zA-Z0-9_]+(?:@[a-zA-Z0-9.\-]+)?)/
    Regex.scan(mention_regex, html)
    |> Enum.map(fn [_, acct] -> %{acct: acct} end)
    |> Enum.uniq_by(& &1.acct)
  end

  defp extract_mentions(_), do: []

  defp tags_for(post_id) do
    {:ok, post_uuid} = Ecto.UUID.dump(post_id)

    query =
      from ph in "post_hashtags",
        join: h in Hybridsocial.Social.Hashtag,
        on: h.id == ph.hashtag_id,
        where: ph.post_id == ^post_uuid,
        select: %{name: h.name}

    base_url = HybridsocialWeb.Endpoint.url()

    Repo.all(query)
    |> Enum.map(fn tag ->
      %{name: tag.name, url: "#{base_url}/tags/#{tag.name}"}
    end)
  end

  defp emojis_in_content(content) do
    # Find :shortcode: patterns in content
    shortcodes =
      ~r/:([a-zA-Z0-9_]+):/
      |> Regex.scan(content)
      |> Enum.map(fn [_, code] -> code end)
      |> Enum.uniq()

    if shortcodes != [] do
      CustomEmoji
      |> where([e], e.shortcode in ^shortcodes and e.enabled == true)
      |> Repo.all()
      |> Enum.map(fn emoji ->
        %{
          shortcode: emoji.shortcode,
          url: emoji.image_url,
          static_url: emoji.image_url,
          category: emoji.category
        }
      end)
    else
      []
    end
  end

  defp in_reply_to_account_id(%{parent: %Hybridsocial.Social.Post{identity_id: id}}), do: id
  defp in_reply_to_account_id(%{parent_id: nil}), do: nil

  defp in_reply_to_account_id(%{parent_id: parent_id}) when is_binary(parent_id) do
    Hybridsocial.Social.Post
    |> where([p], p.id == ^parent_id)
    |> select([p], p.identity_id)
    |> Repo.one()
  end

  defp in_reply_to_account_id(_), do: nil

  defp extract_domain(identity) do
    url = Map.get(identity, :url, nil)

    if url do
      case URI.parse(url) do
        %URI{host: host} when is_binary(host) ->
          local_host = URI.parse(HybridsocialWeb.Endpoint.url()).host
          if host == local_host, do: nil, else: host

        _ ->
          nil
      end
    else
      nil
    end
  end
end
