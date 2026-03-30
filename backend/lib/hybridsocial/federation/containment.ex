defmodule Hybridsocial.Federation.Containment do
  @moduledoc """
  Object containment functions for validating remote ActivityPub objects.

  Ensures that incoming activities originate from the domains they claim to,
  preventing spoofing and SSRF attacks. Removal of these checks is NOT recommended.
  """

  @doc "Extract the actor URI from an activity map."
  def get_actor(%{"actor" => actor}) when is_binary(actor), do: actor

  def get_actor(%{"actor" => actor}) when is_list(actor) do
    case actor do
      [first | _] when is_binary(first) ->
        first

      [first | _] when is_map(first) ->
        case Enum.find(actor, fn
          %{"type" => type} -> type in ["Person", "Service", "Application", "Organization", "Group"]
          _ -> false
        end) do
          %{"id" => id} -> id
          _ -> nil
        end

      _ ->
        nil
    end
  end

  def get_actor(%{"actor" => %{"id" => id}}) when is_binary(id), do: id

  def get_actor(%{"actor" => nil, "attributedTo" => actor}) when not is_nil(actor) do
    get_actor(%{"actor" => actor})
  end

  def get_actor(_), do: nil

  @doc "Extract the object id from an activity map."
  def get_object(%{"object" => id}) when is_binary(id), do: id
  def get_object(%{"object" => %{"id" => id}}) when is_binary(id), do: id
  def get_object(_), do: nil

  @doc """
  Checks that an imported AP object's actor matches the host it came from.
  Returns :ok or :error.
  """
  def contain_origin(_id, %{"actor" => nil}), do: :error

  def contain_origin(id, %{"actor" => _actor} = params) do
    id_uri = URI.parse(id)
    actor_uri = URI.parse(get_actor(params))
    compare_uris(actor_uri, id_uri)
  end

  def contain_origin(id, %{"attributedTo" => actor} = params) do
    contain_origin(id, Map.put(params, "actor", actor))
  end

  def contain_origin(_id, _data), do: :ok

  @doc """
  Checks that an object id is from the same host as the activity id.
  Returns :ok or :error.
  """
  def contain_origin_from_id(id, %{"id" => other_id}) when is_binary(other_id) do
    compare_uris(URI.parse(id), URI.parse(other_id))
  end

  # Mastodon pin activities don't have an id, so check the object field.
  def contain_origin_from_id(id, %{"object" => object}) when is_binary(object) do
    compare_uris(URI.parse(id), URI.parse(object))
  end

  def contain_origin_from_id(_id, _data), do: :error

  @doc "Verify embedded object origin matches the parent."
  def contain_child(%{"object" => %{"id" => id, "attributedTo" => _} = object}) do
    contain_origin(id, object)
  end

  def contain_child(_), do: :ok

  @doc """
  Prevents fetching from our own server (SSRF protection).
  Returns :ok if the id is remote, :error if it's local.
  """
  def contain_local_fetch(id) do
    local_uri = URI.parse(HybridsocialWeb.Endpoint.url())
    id_uri = URI.parse(id)

    case compare_uris(id_uri, local_uri) do
      :ok -> :error
      :error -> :ok
    end
  end

  @doc "Checks whether two URIs belong to the same domain."
  def same_origin(id1, id2) do
    compare_uris(URI.parse(id1), URI.parse(id2))
  end

  # --- Private helpers ---

  defp compare_uris(%URI{host: host}, %URI{host: host}) when is_binary(host), do: :ok
  defp compare_uris(_, _), do: :error
end
