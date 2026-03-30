defmodule HybridsocialWeb.Helpers.Account do
  @moduledoc """
  Shared helper for building the `acct` field (user@domain for remote, handle for local).
  """

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
end
