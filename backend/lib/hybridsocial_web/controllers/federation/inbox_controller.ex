defmodule HybridsocialWeb.Federation.InboxController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Federation
  alias Hybridsocial.Federation.{ActivityMapper, Containment, Inbox, ObjectResolver}

  plug HybridsocialWeb.Plugs.DigestPlug

  require Logger

  @doc """
  Handles POST to /actors/:id/inbox (actor-specific inbox).
  """
  def actor_inbox(conn, _params) do
    # Use body_params, not the merged params — the route's :id would
    # otherwise shadow the activity's own "id" field.
    process_inbox(conn, conn.body_params)
  end

  @doc """
  Handles POST to /inbox (shared inbox).
  """
  def shared_inbox(conn, _params) do
    process_inbox(conn, conn.body_params)
  end

  defp process_inbox(conn, activity) do
    with {:ok, key_id} <- verify_http_signature(conn),
         :ok <- check_sender_policy(activity),
         :ok <- check_dedup(activity),
         {:ok, _result} <- authorize_and_process(activity, key_id) do
      # Record the activity for dedup
      record_activity_dedup(activity)

      conn
      |> put_status(202)
      |> json(%{status: "accepted"})
    else
      {:error, :signature_invalid} ->
        conn
        |> put_status(401)
        |> json(%{error: "Invalid HTTP signature"})

      {:error, :domain_suspended} ->
        conn
        |> put_status(403)
        |> json(%{error: "Domain suspended"})

      {:error, :duplicate_activity} ->
        # Silently accept duplicates to be idempotent
        conn
        |> put_status(202)
        |> json(%{status: "accepted"})

      {:error, reason} ->
        Logger.warning("Inbox processing failed: #{inspect(reason)}")

        conn
        |> put_status(422)
        |> json(%{error: "Unprocessable activity"})
    end
  end

  # Verify HTTP signatures on incoming federation requests. Returns
  # `{:ok, key_id}` so the caller can cross-check the keyId's actor
  # against the activity's claimed actor — without that check, a valid
  # fediverse key can sign an activity claiming to come from anyone.
  defp verify_http_signature(conn) do
    if Application.get_env(:hybridsocial, :federation_signature_check, true) do
      case Hybridsocial.Federation.HTTPSignature.verify(conn) do
        {:ok, key_id} ->
          {:ok, key_id}

        {:error, reason} ->
          Logger.warning("HTTP signature verification failed: #{inspect(reason)}")
          {:error, :signature_invalid}
      end
    else
      # Test/dev bypass — never used in production.
      {:ok, :signature_check_disabled}
    end
  end

  # Cross-check that the keyId of the verified signature corresponds to
  # the actor named in the activity. Without this, an attacker holding
  # any valid fediverse key could sign an activity body claiming to be
  # from a different actor (`{"actor": "https://victim/users/X", ...}`)
  # and we'd happily accept it.
  #
  # The match is at the *origin* level: keyId
  # `https://example.com/users/foo#main-key` may sign for actor
  # `https://example.com/users/foo` (most common) but not for
  # `https://other.com/users/anything`. We compare the URL origin
  # (scheme + host + port) of `key_id` and `activity["actor"]`.
  # Same-origin signing is what every spec-compliant peer does and
  # blocks cross-origin actor spoofing without breaking shared inboxes
  # that legitimately fan out one actor's key across many activities.
  defp check_actor_matches_key(_activity, :signature_check_disabled), do: :ok

  defp check_actor_matches_key(%{"actor" => actor_url}, key_id)
       when is_binary(actor_url) and is_binary(key_id) do
    actor_origin = origin(actor_url)
    key_origin = origin(key_id)

    cond do
      is_nil(actor_origin) or is_nil(key_origin) ->
        Logger.warning("Inbox: missing origin on actor=#{actor_url} keyId=#{key_id}")
        {:error, :signature_invalid}

      actor_origin != key_origin ->
        # Not necessarily an attack: this is what a RELAY or a reply-
        # forwarding server looks like (server B forwards server C's
        # activity, signing the delivery with B's key). We can't trust B's
        # copy, but we can accept the content if it genuinely exists on the
        # author's own origin — see authorize_and_process/2.
        {:error, :cross_origin}

      true ->
        :ok
    end
  end

  defp check_actor_matches_key(_activity, _key_id), do: {:error, :missing_actor}

  # Decide whether to process the delivered activity as-is or, for a
  # cross-origin (forwarded/relayed) delivery, re-derive and process the
  # authentic object from its own origin.
  defp authorize_and_process(activity, key_id) do
    case check_actor_matches_key(activity, key_id) do
      :ok ->
        # Same-origin signature (or signature checks disabled): the signer
        # owns the actor, so the delivered body is trusted.
        Inbox.process(activity)

      {:error, :cross_origin} ->
        verify_forwarded_activity(activity)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # A forwarded/relayed activity is signed by a server other than the
  # author's. Rather than hard-reject it (which silently drops legitimate
  # relayed replies and breaks threads), we dereference the object from ITS
  # OWN origin and process that authentic copy — never the forwarder's. We
  # only accept when the object genuinely lives on, and is authored by, the
  # claimed actor's origin; anything else is treated as spoofing and rejected
  # exactly as before.
  defp verify_forwarded_activity(activity) do
    actor = Containment.get_actor(activity)
    object_id = Containment.get_object(activity)
    actor_origin = actor && origin(actor)

    cond do
      is_nil(actor_origin) or is_nil(object_id) ->
        log_forward_reject("no dereferenceable object", activity)
        {:error, :signature_invalid}

      origin(object_id) != actor_origin ->
        # The object isn't hosted on the claimed author's server.
        log_forward_reject("object #{object_id} off actor origin #{actor_origin}", activity)
        {:error, :signature_invalid}

      true ->
        case ObjectResolver.resolve(object_id) do
          {:ok, obj} when is_map(obj) ->
            author = obj["attributedTo"] || obj["actor"]

            if origin(actor_id(author)) == actor_origin do
              Logger.info("Inbox: accepted forwarded activity via origin fetch of #{object_id}")
              # Trust ONLY the freshly-fetched object, not the forwarder's.
              Inbox.process(Map.put(activity, "object", obj))
            else
              log_forward_reject("fetched object attributedTo mismatch (#{object_id})", activity)
              {:error, :signature_invalid}
            end

          other ->
            log_forward_reject("dereference failed #{inspect(other)} (#{object_id})", activity)
            {:error, :signature_invalid}
        end
    end
  end

  # attributedTo/actor may be a bare id or an embedded map.
  defp actor_id(id) when is_binary(id), do: id
  defp actor_id(%{"id" => id}) when is_binary(id), do: id
  defp actor_id(_), do: nil

  # `ld_signed` and `public` measure whether verifying Linked Data
  # signatures (RsaSignature2017, which Mastodon attaches to forwarded
  # activities) would recover these: an unsigned or non-public activity
  # can't be recovered that way.
  defp log_forward_reject(why, activity) do
    actor = Containment.get_actor(activity)
    ld_signed = is_map(activity["signature"])

    public =
      [activity["to"], activity["cc"]]
      |> Enum.flat_map(&List.wrap/1)
      |> Enum.any?(
        &(&1 in ["https://www.w3.org/ns/activitystreams#Public", "as:Public", "Public"])
      )

    Logger.warning(
      "Inbox: forwarded activity rejected — #{why} (actor #{inspect(actor)}) " <>
        "ld_signed=#{ld_signed} public=#{public} type=#{activity["type"]}"
    )
  end

  defp origin(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when is_binary(scheme) and is_binary(host) ->
        port = if URI.parse(url).port, do: ":#{URI.parse(url).port}", else: ""
        "#{scheme}://#{host}#{port}"

      _ ->
        nil
    end
  end

  # Check instance policy for the sender's domain using the Federation context.
  defp check_sender_policy(%{"actor" => actor_ap_id}) when is_binary(actor_ap_id) do
    domain = ActivityMapper.extract_domain(actor_ap_id)

    if domain do
      if Federation.domain_allowed?(domain) do
        :ok
      else
        {:error, :domain_suspended}
      end
    else
      {:error, :invalid_actor}
    end
  end

  defp check_sender_policy(_), do: {:error, :missing_actor}

  # Check for duplicate activities using the Federation dedup system.
  defp check_dedup(%{"id" => activity_id}) when is_binary(activity_id) do
    activity_hash = :crypto.hash(:sha256, activity_id) |> Base.encode16(case: :lower)

    if Federation.deduplicate?(activity_hash) do
      {:error, :duplicate_activity}
    else
      :ok
    end
  end

  defp check_dedup(_), do: :ok

  # Record a processed activity for future dedup checks.
  defp record_activity_dedup(%{"id" => activity_id}) when is_binary(activity_id) do
    activity_hash = :crypto.hash(:sha256, activity_id) |> Base.encode16(case: :lower)
    Federation.record_dedup(activity_hash, activity_id)
  end

  defp record_activity_dedup(_), do: :ok
end
