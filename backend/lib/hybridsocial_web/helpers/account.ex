defmodule HybridsocialWeb.Helpers.Account do
  @moduledoc """
  Shared helpers for shaping Account JSON at the HTTP API boundary.

  Keeps translation logic in one place — our internal atom for
  business/brand/page accounts is `:organization` (matching the
  ActivityPub Actor type we federate as), but the public HTTP API
  and frontend call them "page". AP serialization continues to emit
  the canonical `"Organization"`; only our own API surfaces use
  `"page"`.
  """

  @doc """
  The URL to serve for an account/group/page image (avatar, header).

  A remote server's image goes through the signed media proxy, like post
  media: loading it straight from the origin would hand every viewer's IP
  to that server (e.g. pbs.twimg.com for bird.makeup accounts). Local and
  media-host URLs, relative paths and nil come back unchanged; with the
  proxy disabled `MediaProxy.url/1` returns the URL as is.
  """
  def remote_image("http://" <> _ = url), do: Hybridsocial.Media.MediaProxy.url(url)
  def remote_image("https://" <> _ = url), do: Hybridsocial.Media.MediaProxy.url(url)
  def remote_image(other), do: other

  @doc """
  An account's custom emoji (display name / bio) with each image routed
  through `remote_image/1`. Entries keep their shape and key type.
  """
  def remote_emojis(emojis) when is_list(emojis) do
    Enum.map(emojis, fn
      %{} = emoji ->
        Enum.reduce(["url", "static_url", :url, :static_url], emoji, fn key, acc ->
          case acc do
            %{^key => value} -> Map.put(acc, key, remote_image(value))
            _ -> acc
          end
        end)

      other ->
        other
    end)
  end

  def remote_emojis(_), do: []

  @doc """
  Returns the acct string for an identity.
  For local identities: just the handle.
  For remote identities: username@domain extracted from ap_actor_url.
  """
  def build_acct(identity) do
    local_domain = HybridsocialWeb.Endpoint.host()

    case identity.ap_actor_url do
      nil ->
        identity.handle

      ap_url ->
        domain = URI.parse(ap_url).host

        if domain == local_domain do
          identity.handle
        else
          username =
            case URI.parse(ap_url).path do
              nil -> identity.handle
              path -> path |> String.split("/") |> List.last()
            end

          "#{username}@#{domain}"
        end
    end
  end

  @doc """
  The host of a remote identity's origin instance, or `nil` for local
  identities. Used by the frontend both to flag an account as remote and
  to label the "view on original instance" link.
  """
  def remote_domain(%Hybridsocial.Accounts.Identity{is_local: true}), do: nil

  def remote_domain(%Hybridsocial.Accounts.Identity{ap_actor_url: ap_url})
      when is_binary(ap_url) do
    host = URI.parse(ap_url).host

    if host in [nil, HybridsocialWeb.Endpoint.host()], do: nil, else: host
  end

  def remote_domain(_), do: nil

  @doc """
  The human HTML profile URL to link to for a remote identity (AP `url`,
  falling back to its AP id), or `nil` for local identities.
  """
  def profile_url(%Hybridsocial.Accounts.Identity{is_local: true}), do: nil

  def profile_url(%Hybridsocial.Accounts.Identity{} = identity),
    do: identity.profile_url || identity.ap_actor_url

  def profile_url(_), do: nil

  @doc """
  Translates the internal identity type to its public API name.
  `"organization"` becomes `"page"`; everything else passes through
  unchanged. Accepts both strings and atoms.
  """
  def api_type(:organization), do: "page"
  def api_type("organization"), do: "page"
  def api_type(nil), do: nil
  def api_type(type) when is_atom(type), do: Atom.to_string(type)
  def api_type(type) when is_binary(type), do: type
  def api_type(_), do: nil

  @doc """
  Minimal identity shape for embedding inside another resource's
  JSON (message sender, notification actor, post author, etc.).
  Always emits both `handle` (our internal, collision-safe string)
  and `acct` (the display form: `user` for locals, `user@host` for
  remotes). Frontend prefers `acct` when present.

  Callers that render an identity in a list should use this instead
  of spelling out the shape inline — that drift is what leaves
  remote accounts showing their munged handle in one view and the
  real webfinger form in another.
  """
  def serialize_summary(nil), do: nil

  # A soft-deleted account (admin deletion) is scrubbed to a neutral
  # placeholder. It still surfaces in DMs the other party kept, so the
  # survivor sees "Deleted User" instead of the old handle/name/avatar.
  def serialize_summary(%Hybridsocial.Accounts.Identity{deleted_at: deleted} = identity)
      when not is_nil(deleted) do
    %{
      id: identity.id,
      handle: "deleted",
      acct: "deleted",
      display_name: "Deleted User",
      avatar_url: nil,
      emojis: [],
      domain: nil,
      url: nil,
      created_at: identity.inserted_at
    }
  end

  def serialize_summary(%Hybridsocial.Accounts.Identity{} = identity) do
    %{
      id: identity.id,
      handle: identity.handle,
      acct: build_acct(identity),
      display_name: identity.display_name,
      avatar_url: HybridsocialWeb.Helpers.Account.remote_image(identity.avatar_url),
      # Custom emojis so `:shortcode:` in the display_name renders wherever
      # an account appears in a list (post author, notifications, etc.).
      emojis: remote_emojis(identity.emojis || []),
      domain: remote_domain(identity),
      url: profile_url(identity),
      # Mastodon's Account.created_at is non-null; a client that gets a null
      # here fails to deserialize the whole notification.
      created_at: identity.inserted_at
    }
  end
end
