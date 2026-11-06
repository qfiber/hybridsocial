defmodule Hybridsocial.Social.QuoteVisibility do
  @moduledoc """
  Decides whether a viewer may see a quoted post embedded in another post.

  Quoting anything is only a pointer, so being able to read the outer post says
  nothing about the quoted one. It has to clear, for this viewer, the same rules
  as reading it directly, plus moderation:

    * A deleted post is never shown.
    * Its author always sees it, unless deleted.
    * Staff skip the moderation rules so they can review, but not the privacy
      ones: a staff role doesn't open someone's direct messages.
    * A hidden post, or one by a suspended or shadow-banned author, isn't shown.
    * A silenced author's post is shown only to their followers, as on a timeline.
    * Authors the viewer blocked, muted, or who blocked them aren't shown, nor are
      those on a domain the viewer blocked.
    * What remains follows the post's own visibility.

  Everything is resolved for a whole page at once, so a feed of quotes doesn't
  become a query per post. Only non-public quotes, which are rare, check singly.
  """
  import Ecto.Query

  alias Hybridsocial.Accounts.Identity
  alias Hybridsocial.Feeds.Visibility
  alias Hybridsocial.Repo
  alias Hybridsocial.Social.{Block, Follow, Mute, Posts}

  @doc "The ids of the given quoted posts this viewer may see, as a MapSet."
  def readable_ids([], _viewer_id, _staff?), do: MapSet.new()

  def readable_ids(quotes, viewer_id, staff?) do
    authors = quotes |> Enum.map(& &1.identity_id) |> Enum.uniq()

    context = %{
      viewer_id: viewer_id,
      staff?: staff? == true,
      suspended: Visibility.suspended_among(authors),
      shadow_banned: shadow_banned_among(authors),
      publicly_hidden: publicly_hidden_among(authors),
      viewer_hidden: hidden_by_viewer(authors, viewer_id),
      followed: followed_among(authors, viewer_id)
    }

    quotes
    |> Enum.filter(&readable?(&1, context))
    |> MapSet.new(& &1.id)
  end

  @doc """
  Of the given authors, those hidden from this viewer by a block in either
  direction, a mute, or a blocked domain, as a MapSet.
  """
  def hidden_by_viewer(_authors, nil), do: MapSet.new()
  def hidden_by_viewer([], _viewer_id), do: MapSet.new()

  def hidden_by_viewer(authors, viewer_id) do
    now = DateTime.utc_now()

    blocked =
      from(b in Block,
        where:
          (b.blocker_id == ^viewer_id and b.blocked_id in ^authors) or
            (b.blocked_id == ^viewer_id and b.blocker_id in ^authors),
        select: {b.blocker_id, b.blocked_id}
      )
      |> Repo.all()
      |> Enum.flat_map(&Tuple.to_list/1)

    muted =
      from(m in Mute,
        where:
          m.muter_id == ^viewer_id and m.muted_id in ^authors and
            (is_nil(m.expires_at) or m.expires_at > ^now),
        select: m.muted_id
      )
      |> Repo.all()

    # Same derivation as `Social.Streams`: identities carry no domain column.
    on_blocked_domain =
      from(i in Identity,
        where: i.id in ^authors and i.is_local == false and not is_nil(i.ap_actor_url),
        where:
          fragment(
            "EXISTS (SELECT 1 FROM user_domain_blocks udb WHERE udb.identity_id = ? AND udb.domain = lower(split_part(split_part(?, '/', 3), ':', 1)))",
            type(^viewer_id, Ecto.UUID),
            i.ap_actor_url
          ),
        select: i.id
      )
      |> Repo.all()

    (blocked ++ muted ++ on_blocked_domain)
    |> MapSet.new()
    |> MapSet.delete(viewer_id)
  end

  defp readable?(%{deleted_at: deleted_at}, _context) when not is_nil(deleted_at), do: false
  defp readable?(%{identity_id: id}, %{viewer_id: id}) when not is_nil(id), do: true

  defp readable?(quote_post, %{staff?: true, viewer_id: viewer_id}) do
    Posts.viewer_can_read?(quote_post, viewer_id)
  end

  defp readable?(quote_post, context) do
    author = quote_post.identity_id

    cond do
      not is_nil(quote_post.hidden_at) -> false
      MapSet.member?(context.suspended, author) -> false
      MapSet.member?(context.shadow_banned, author) -> false
      MapSet.member?(context.viewer_hidden, author) -> false
      silenced_and_not_followed?(author, context) -> false
      true -> Posts.viewer_can_read?(quote_post, context.viewer_id)
    end
  end

  defp silenced_and_not_followed?(author, context) do
    MapSet.member?(context.publicly_hidden, author) and
      not MapSet.member?(context.followed, author)
  end

  defp shadow_banned_among(authors) do
    from(i in Identity, where: i.id in ^authors and i.is_shadow_banned == true, select: i.id)
    |> Repo.all()
    |> MapSet.new()
  end

  # Suspended and shadow-banned authors are refused before this is consulted, so
  # what it adds is silenced accounts and silenced domains.
  defp publicly_hidden_among(authors) do
    from(i in Identity,
      where: i.id in ^authors and i.id in subquery(Visibility.publicly_hidden_author_ids()),
      select: i.id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  defp followed_among(_authors, nil), do: MapSet.new()

  defp followed_among(authors, viewer_id) do
    from(f in Follow,
      where: f.follower_id == ^viewer_id and f.followee_id in ^authors and f.status == :accepted,
      select: f.followee_id
    )
    |> Repo.all()
    |> MapSet.new()
  end
end
