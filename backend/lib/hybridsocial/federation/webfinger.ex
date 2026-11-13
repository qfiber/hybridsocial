defmodule Hybridsocial.Federation.WebFinger do
  @moduledoc """
  WebFinger logic for ActivityPub federation.
  """

  alias Hybridsocial.Accounts

  @doc """
  Returns the WebFinger JRD representation for a local identity.
  """
  def represent(:instance_actor) do
    domain = HybridsocialWeb.Endpoint.host()
    actor = Hybridsocial.Federation.InstanceActor.ap_id()

    %{
      "subject" => "acct:#{domain}@#{domain}",
      "aliases" => [actor],
      "links" => [
        %{"rel" => "self", "type" => "application/activity+json", "href" => actor}
      ]
    }
  end

  def represent(identity) do
    domain = HybridsocialWeb.Endpoint.host()

    %{
      "subject" => "acct:#{identity.handle}@#{domain}",
      "aliases" => [
        identity.ap_actor_url
      ],
      "links" => [
        %{
          "rel" => "self",
          "type" => "application/activity+json",
          "href" => identity.ap_actor_url
        },
        %{
          "rel" => "http://webfinger.net/rel/profile-page",
          "type" => "text/html",
          "href" => identity.ap_actor_url
        }
      ]
    }
  end

  @doc """
  Looks up a remote actor via WebFinger.
  `acct` should be in the format "user@domain".
  """
  def finger(acct) do
    [_user, domain] = String.split(acct, "@", parts: 2)

    # SSRF protection: validate domain before making request
    with :ok <- Hybridsocial.Security.UrlValidator.validate_domain(domain) do
      url = "https://#{domain}/.well-known/webfinger?resource=acct:#{URI.encode(acct)}"

      # WebFinger (RFC 7033) is intentionally unsigned. Peers serve it
      # without authorized-fetch because it's how new instances discover
      # each other before any keys exist. Do not route through SignedFetch.
      headers = [
        {"Accept", "application/jrd+json"},
        {"User-Agent", "HybridSocial (+https://#{HybridsocialWeb.Endpoint.host()})"}
      ]

      case Hybridsocial.HTTP.get(url, headers, recv_timeout: 10_000, timeout: 10_000) do
        {:ok, %{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, data} ->
              ap_id =
                data
                |> Map.get("links", [])
                |> Enum.find(fn link ->
                  link["rel"] == "self" && link["type"] == "application/activity+json"
                end)
                |> case do
                  nil -> nil
                  link -> link["href"]
                end

              {:ok, %{data: data, ap_id: ap_id}}

            {:error, _} ->
              {:error, :invalid_response}
          end

        {:ok, %{status_code: 404}} ->
          {:error, :not_found}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Resolves a local acct URI, returning the identity if found.
  """
  # The instance actor (`/actor`, preferredUsername = our domain) is the
  # keyId of every signed GET we make. Mastodon re-resolves a stale actor by
  # WebFinger on its handle before refetching its key; a 404 here made it
  # refuse all our signed fetches ("Could not refresh public key").
  def resolve_local(resource) do
    instance_actor = Hybridsocial.Federation.InstanceActor.ap_id()

    case parse_resource(resource) do
      _ when resource == instance_actor ->
        {:ok, :instance_actor}

      {:ok, handle, domain} ->
        local_domain = HybridsocialWeb.Endpoint.host()

        cond do
          domain != local_domain -> {:error, :not_local}
          instance_actor_username?(handle, local_domain) -> {:ok, :instance_actor}
          true -> resolve_local_handle(handle)
        end

      :error ->
        {:error, :invalid_resource}
    end
  end

  # The instance actor's username is our host, so it changes when the
  # instance moves domain, and peers that cached the actor still look it up
  # by the old name (mastodon.social asks for acct:<old host>@<our host>).
  # `instance_actor_legacy_usernames` lists those old names; we answer with
  # the current subject and Mastodon follows that rename.
  defp instance_actor_username?(handle, local_domain) do
    handle = String.downcase(handle)
    handle == String.downcase(local_domain) or handle in legacy_instance_actor_usernames()
  end

  defp legacy_instance_actor_usernames do
    case Hybridsocial.Config.get("instance_actor_legacy_usernames", []) do
      names when is_list(names) ->
        Enum.map(names, &(&1 |> to_string() |> String.downcase()))

      names when is_binary(names) ->
        names
        |> String.split(",", trim: true)
        |> Enum.map(&(&1 |> String.trim() |> String.downcase()))

      _ ->
        []
    end
  end

  defp resolve_local_handle(handle) do
    case Accounts.get_identity_by_handle(handle) do
      nil -> {:error, :not_found}
      identity -> {:ok, identity}
    end
  end

  defp parse_resource("acct:" <> acct) do
    case String.split(acct, "@", parts: 2) do
      [handle, domain] -> {:ok, handle, domain}
      _ -> :error
    end
  end

  defp parse_resource(_), do: :error
end
