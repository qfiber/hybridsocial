defmodule Hybridsocial.Federation.WebFinger do
  @moduledoc """
  WebFinger logic for ActivityPub federation.
  """

  alias Hybridsocial.Accounts

  @doc """
  Returns the WebFinger JRD representation for a local identity.
  """
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

      headers = [
        {"Accept", "application/jrd+json"},
        {"User-Agent", "HybridSocial (+https://#{HybridsocialWeb.Endpoint.host()})"}
      ]

      case HTTPoison.get(url, headers, recv_timeout: 10_000, timeout: 10_000) do
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
  def resolve_local(resource) do
    case parse_resource(resource) do
      {:ok, handle, domain} ->
        local_domain = HybridsocialWeb.Endpoint.host()

        if domain == local_domain do
          case Accounts.get_identity_by_handle(handle) do
            nil -> {:error, :not_found}
            identity -> {:ok, identity}
          end
        else
          {:error, :not_local}
        end

      :error ->
        {:error, :invalid_resource}
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
