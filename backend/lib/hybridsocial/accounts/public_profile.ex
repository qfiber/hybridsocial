defmodule Hybridsocial.Accounts.PublicProfile do
  @moduledoc """
  What a logged-out visitor, and a search engine, may see of a local account.

  Two separate questions:

    * `public?/1`: may the page be viewed without logging in? Any local account
      in good standing, unless the instance has closed itself with
      `public_timeline_access = "none"`. A locked account's page still shows, but
      only its public posts, as for any non-follower.
    * `indexable?/1`: may search engines index it? On top of being public, the
      person must have left `discoverable` and `allow_unfurl` on, the account
      can't be locked or silenced, and staff can't have set
      `search_indexing_blocked`. Staff block indexing without affecting whether
      the page can be viewed.

  A remote account's home is elsewhere, so it is neither.
  """
  alias Hybridsocial.Config

  @public_types ~w(user bot)

  def public?(identity) do
    Config.get("public_timeline_access", "all") != "none" and
      identity.is_local == true and
      identity.type in @public_types and
      is_nil(identity.deleted_at) and
      identity.is_suspended == false and
      identity.is_shadow_banned == false
  end

  def indexable?(identity) do
    public?(identity) and
      identity.discoverable == true and
      identity.allow_unfurl == true and
      identity.is_locked == false and
      identity.is_silenced == false and
      identity.search_indexing_blocked == false
  end
end
