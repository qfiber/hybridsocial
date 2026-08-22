defmodule Hybridsocial.Messaging do
  @moduledoc """
  The Messaging context. Manages conversations, messages, and DM preferences.
  """
  import Ecto.Query
  require Logger

  alias Hybridsocial.Repo

  alias Hybridsocial.Messaging.{
    Conversation,
    Participant,
    Message,
    DeliveryStatus,
    DmPreference,
    MessageReaction
  }

  alias Hybridsocial.Social

  # ---------------------------------------------------------------------------
  # Conversations
  # ---------------------------------------------------------------------------

  @doc "Find an existing direct conversation between two identities, or create one."
  def find_or_create_direct(sender_id, recipient_id) do
    with :ok <- check_not_self(sender_id, recipient_id),
         :ok <- check_can_dm(sender_id, recipient_id),
         :ok <- check_peer_supports_dm(recipient_id) do
      case find_direct_conversation(sender_id, recipient_id) do
        %Conversation{} = conv ->
          {:ok, conv}

        nil ->
          create_direct_conversation(sender_id, recipient_id)
      end
    end
  end

  # DMs across the fediverse only work where the peer software speaks
  # a real chat primitive (ChatMessage). For everyone else — Mastodon,
  # Misskey, unknown — we surface `{:error, :dm_not_supported, ...}`
  # so the caller can fall back to a direct-visibility post. The
  # tuple carries the recipient's ap_actor_url + handle so the
  # frontend can compose the fallback post without re-fetching.
  defp check_peer_supports_dm(recipient_id) do
    case Repo.get(Hybridsocial.Accounts.Identity, recipient_id) do
      nil ->
        {:error, :recipient_not_found}

      %Hybridsocial.Accounts.Identity{ap_actor_url: nil} ->
        # Local recipient — always supported.
        :ok

      %Hybridsocial.Accounts.Identity{ap_actor_url: url} = identity ->
        if identity_is_local?(identity) do
          :ok
        else
          if Hybridsocial.Federation.NodeInfo.chat_capable?(url) do
            :ok
          else
            {:error, :dm_not_supported,
             %{
               recipient_id: recipient_id,
               ap_actor_url: url,
               handle: identity.handle,
               display_name: identity.display_name
             }}
          end
        end
    end
  end

  defp check_not_self(id, id), do: {:error, :cannot_message_self}
  defp check_not_self(_a, _b), do: :ok

  defp check_can_dm(sender_id, recipient_id) do
    if can_dm?(sender_id, recipient_id) do
      :ok
    else
      {:error, :dm_not_allowed}
    end
  end

  defp find_direct_conversation(identity_a, identity_b) do
    Conversation
    |> where([c], c.type == "direct")
    |> join(:inner, [c], p1 in Participant,
      on: p1.conversation_id == c.id and p1.identity_id == ^identity_a and is_nil(p1.left_at)
    )
    |> join(:inner, [c, _p1], p2 in Participant,
      on: p2.conversation_id == c.id and p2.identity_id == ^identity_b and is_nil(p2.left_at)
    )
    |> limit(1)
    |> Repo.one()
  end

  defp create_direct_conversation(sender_id, recipient_id) do
    now = DateTime.utc_now()
    is_local = identity_is_local?(sender_id) and identity_is_local?(recipient_id)

    Ecto.Multi.new()
    |> Ecto.Multi.insert(
      :conversation,
      Conversation.changeset(%Conversation{}, %{
        type: "direct",
        accepted: true,
        is_local: is_local
      })
    )
    |> Ecto.Multi.insert(:participant_sender, fn %{conversation: conv} ->
      Participant.changeset(%Participant{}, %{
        conversation_id: conv.id,
        identity_id: sender_id,
        joined_at: now
      })
    end)
    |> Ecto.Multi.insert(:participant_recipient, fn %{conversation: conv} ->
      Participant.changeset(%Participant{}, %{
        conversation_id: conv.id,
        identity_id: recipient_id,
        joined_at: now
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{conversation: conversation}} ->
        {:ok, conversation}

      {:error, _step, changeset, _changes} ->
        {:error, changeset}
    end
  end

  defp identity_is_local?(%Hybridsocial.Accounts.Identity{} = identity),
    do: Hybridsocial.Federation.LocalUrl.local_identity?(identity)

  defp identity_is_local?(identity_id) when is_binary(identity_id) do
    case Repo.get(Hybridsocial.Accounts.Identity, identity_id) do
      nil -> false
      identity -> Hybridsocial.Federation.LocalUrl.local_identity?(identity)
    end
  end

  defp identity_is_local?(_), do: false

  @doc "Create a group DM with multiple participants."
  def create_group_dm(creator_id, participant_ids) when is_list(participant_ids) do
    all_ids = Enum.uniq([creator_id | participant_ids])

    if length(all_ids) < 2 do
      {:error, :insufficient_participants}
    else
      now = DateTime.utc_now()

      multi =
        Ecto.Multi.new()
        |> Ecto.Multi.insert(
          :conversation,
          Conversation.changeset(%Conversation{}, %{type: "group_dm", accepted: true})
        )

      multi =
        all_ids
        |> Enum.with_index()
        |> Enum.reduce(multi, fn {identity_id, idx}, acc ->
          Ecto.Multi.insert(acc, :"participant_#{idx}", fn %{conversation: conv} ->
            Participant.changeset(%Participant{}, %{
              conversation_id: conv.id,
              identity_id: identity_id,
              joined_at: now
            })
          end)
        end)

      multi
      |> Repo.transaction()
      |> case do
        {:ok, %{conversation: conversation}} ->
          {:ok, conversation}

        {:error, _step, changeset, _changes} ->
          {:error, changeset}
      end
    end
  end

  @doc "Get a conversation by id, verifying the identity is a participant."
  def get_conversation(id, identity_id) do
    case Repo.get(Conversation, id) do
      nil ->
        {:error, :not_found}

      conversation ->
        if participant?(id, identity_id) do
          {:ok, conversation |> Repo.preload([:participants]) |> annotate(identity_id)}
        else
          {:error, :not_found}
        end
    end
  end

  @doc "List all conversations for an identity, sorted by last message, paginated."
  def list_conversations(identity_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)

    Conversation
    |> join(:inner, [c], p in Participant,
      on: p.conversation_id == c.id and p.identity_id == ^identity_id and is_nil(p.left_at)
    )
    |> order_by([c], desc: c.updated_at)
    |> limit(^limit)
    |> offset(^offset)
    |> preload([:participants])
    |> Repo.all()
    |> Enum.map(&annotate(&1, identity_id))
  end

  # Populates the virtual `last_message` and `unread_count` fields on a
  # conversation struct. Called from list/get so the inbox can render
  # preview + badge without an extra round-trip per conversation.
  defp annotate(%Conversation{} = conversation, identity_id) do
    last_message =
      Message
      |> where([m], m.conversation_id == ^conversation.id and is_nil(m.deleted_at))
      |> order_by([m], desc: m.created_at)
      |> limit(1)
      |> Repo.one()
      |> case do
        nil -> nil
        msg -> decrypt_message(msg)
      end

    unread_count = unread_count_for(conversation.id, identity_id)

    %{conversation | last_message: last_message, unread_count: unread_count}
  end

  defp unread_count_for(conversation_id, identity_id) do
    participant =
      Participant
      |> where(
        [p],
        p.conversation_id == ^conversation_id and p.identity_id == ^identity_id and
          is_nil(p.left_at)
      )
      |> Repo.one()

    case participant do
      nil ->
        0

      %Participant{last_read_message_id: nil} ->
        Message
        |> where([m], m.conversation_id == ^conversation_id and is_nil(m.deleted_at))
        |> where([m], m.sender_id != ^identity_id)
        |> Repo.aggregate(:count, :id)

      %Participant{last_read_message_id: last_read_id} ->
        last_read_at =
          Message
          |> where([m], m.id == ^last_read_id)
          |> select([m], m.created_at)
          |> Repo.one()

        case last_read_at do
          nil ->
            0

          dt ->
            Message
            |> where([m], m.conversation_id == ^conversation_id and is_nil(m.deleted_at))
            |> where([m], m.sender_id != ^identity_id)
            |> where([m], m.created_at > ^dt)
            |> Repo.aggregate(:count, :id)
        end
    end
  end

  @doc """
  Delete a conversation from the caller's view.

  Mechanically the same primitive as `leave_conversation/2` (sets
  the participant's `left_at`), but works for both direct and group
  DMs and sends no notification to the other participants. The
  conversation row + messages stay so the other side keeps their
  copy until they too delete it; periodic sweeper hard-deletes
  conversations once all participants have left_at set.
  """
  def delete_conversation(conversation_id, identity_id) do
    Participant
    |> where(
      [p],
      p.conversation_id == ^conversation_id and p.identity_id == ^identity_id and
        is_nil(p.left_at)
    )
    |> Repo.one()
    |> case do
      nil ->
        {:error, :not_found}

      participant ->
        case participant
             |> Ecto.Changeset.change(left_at: DateTime.utc_now())
             |> Repo.update() do
          {:ok, _} = ok ->
            # On remote peers each DM is stored as a Status (Mastodon has
            # no concept of conversation-level delete). Fan out a Delete
            # activity for every message this user sent in the thread so
            # the remote side's inbox mirrors our "conversation gone".
            fan_out_dm_deletes(conversation_id, identity_id)
            ok

          err ->
            err
        end
    end
  end

  # Fires a Delete{Tombstone} activity for each local message the caller
  # sent in this conversation, to every remote participant. Fire-and-
  # forget — we don't block the delete response on federation.
  defp fan_out_dm_deletes(conversation_id, identity_id) do
    sender = Repo.get(Hybridsocial.Accounts.Identity, identity_id)

    if sender && is_binary(sender.private_key) do
      messages =
        Message
        |> where(
          [m],
          m.conversation_id == ^conversation_id and m.sender_id == ^identity_id and
            is_nil(m.deleted_at) and not is_nil(m.ap_id)
        )
        |> Repo.all()

      remote_participants =
        Participant
        |> where([p], p.conversation_id == ^conversation_id and p.identity_id != ^identity_id)
        |> join(:inner, [p], i in Hybridsocial.Accounts.Identity, on: i.id == p.identity_id)
        |> where([p, i], not is_nil(i.ap_actor_url))
        |> select([p, i], i)
        |> Repo.all()
        |> Enum.reject(&identity_is_local?/1)

      for message <- messages, recipient <- remote_participants do
        activity = build_dm_delete(sender, recipient, message)
        Hybridsocial.Federation.Publisher.publish(activity, sender)
      end
    end
  end

  defp build_dm_delete(sender, recipient, message) do
    base = HybridsocialWeb.Endpoint.url()
    sender_url = "#{base}/actors/#{sender.id}"
    activity_id = "#{base}/activities/#{sender.id}/delete-dm/#{message.id}"

    %{
      "@context" => [
        "https://www.w3.org/ns/activitystreams",
        "https://w3id.org/security/v1"
      ],
      "id" => activity_id,
      "type" => "Delete",
      "actor" => sender_url,
      "to" => [recipient.ap_actor_url],
      # Tombstone: per AS, a Delete of a note should reference the note
      # URL. Mastodon accepts both a string URI and a Tombstone object;
      # the string form is simpler and what most servers emit.
      "object" => message.ap_id
    }
  end

  @doc "Leave a conversation (group DMs only)."
  def leave_conversation(conversation_id, identity_id) do
    case Repo.get(Conversation, conversation_id) do
      nil ->
        {:error, :not_found}

      %Conversation{type: "direct"} ->
        {:error, :cannot_leave_direct}

      %Conversation{type: "group_dm"} ->
        Participant
        |> where(
          [p],
          p.conversation_id == ^conversation_id and p.identity_id == ^identity_id and
            is_nil(p.left_at)
        )
        |> Repo.one()
        |> case do
          nil ->
            {:error, :not_found}

          participant ->
            participant
            |> Ecto.Changeset.change(left_at: DateTime.utc_now())
            |> Repo.update()
        end
    end
  end

  @doc "Mute a conversation."
  def mute_conversation(conversation_id, identity_id) do
    update_notifications(conversation_id, identity_id, false)
  end

  @doc "Unmute a conversation."
  def unmute_conversation(conversation_id, identity_id) do
    update_notifications(conversation_id, identity_id, true)
  end

  defp update_notifications(conversation_id, identity_id, enabled) do
    Participant
    |> where(
      [p],
      p.conversation_id == ^conversation_id and p.identity_id == ^identity_id and
        is_nil(p.left_at)
    )
    |> Repo.one()
    |> case do
      nil ->
        {:error, :not_found}

      participant ->
        participant
        |> Ecto.Changeset.change(notifications_enabled: enabled)
        |> Repo.update()
    end
  end

  # ---------------------------------------------------------------------------
  # Messages
  # ---------------------------------------------------------------------------

  @doc "Send a message in a conversation."
  def send_message(conversation_id, sender_id, attrs) do
    unless participant?(conversation_id, sender_id) do
      {:error, :not_found}
    else
      now = DateTime.utc_now()

      # Capture the plaintext before we replace it with ciphertext in
      # the encrypted_attrs — federation to remote participants needs
      # the cleartext. Mastodon + friends don't speak our at-rest
      # cipher, and DMs with remote users are explicitly not E2EE
      # (the UI warns about this too).
      plaintext = attrs["content"] || ""

      # Allocate the message ID up-front so we can derive its AP URL
      # and persist it in the same insert. The URL is what outbound
      # Create activities embed as `object.id` and is what later
      # messages in the same thread reference via `inReplyTo`.
      message_id = Ecto.UUID.generate()
      ap_id = "#{HybridsocialWeb.Endpoint.url()}/dm/#{message_id}"

      with {:ok, encrypted_attrs} <- encrypt_message_attrs(conversation_id, sender_id, attrs) do
        encrypted_attrs =
          encrypted_attrs
          |> Map.put("id", message_id)
          |> Map.put("ap_id", ap_id)

        case do_send_message(conversation_id, sender_id, encrypted_attrs, now) do
          {:ok, message} = result ->
            maybe_federate_dm(conversation_id, sender_id, message, plaintext)
            result

          other ->
            other
        end
      end
    end
  end

  # Delivers a Direct Create{Note} activity to every remote participant
  # in the conversation. Fire-and-forget — delivery failures log but
  # don't fail the local send. For a 1-on-1 or group DM with ONLY
  # local participants, this is a no-op.
  defp maybe_federate_dm(conversation_id, sender_id, message, plaintext) do
    sender = Hybridsocial.Repo.get(Hybridsocial.Accounts.Identity, sender_id)

    if sender && is_binary(sender.private_key) do
      remote_participants =
        Participant
        |> where([p], p.conversation_id == ^conversation_id and is_nil(p.left_at))
        |> where([p], p.identity_id != ^sender_id)
        |> join(:inner, [p], i in Hybridsocial.Accounts.Identity, on: i.id == p.identity_id)
        |> where([p, i], not is_nil(i.ap_actor_url))
        |> select([p, i], i)
        |> Repo.all()

      Enum.each(remote_participants, fn recipient ->
        activity = build_dm_activity(sender, recipient, message, plaintext)
        # Route through `publish/2` instead of `deliver/3` so DM
        # delivery rides the same retry queue as posts. Transient
        # peer failures (502, connection reset) now retry with
        # backoff instead of dropping the message on first error.
        Hybridsocial.Federation.Publisher.publish(activity, sender)
      end)
    end
  end

  @doc """
  Ingests a DM received from a remote actor via ActivityPub. Finds or
  creates the direct conversation between sender and local recipient,
  encrypts the plaintext, and inserts the message with `is_local: false`
  so the UI surfaces the "federated / not encrypted" warning.

  Unlike `send_message/3`, this path does NOT re-federate — the sender
  is remote and already delivered to every other peer.
  """
  def ingest_remote_dm(
        %Hybridsocial.Accounts.Identity{} = sender,
        %Hybridsocial.Accounts.Identity{} = recipient,
        attrs
      ) do
    plaintext = Map.get(attrs, :content, "")
    remote_ap_id = Map.get(attrs, :ap_id)

    # Idempotency: Mastodon retries deliveries on 5xx/network errors,
    # and the ap_id is the stable origin URL. Short-circuit if we
    # already have this note on file.
    case remote_ap_id && Repo.get_by(Message, ap_id: remote_ap_id) do
      %Message{} = existing ->
        {:ok, decrypt_message(existing)}

      _ ->
        with {:ok, conv} <- find_or_create_direct(sender.id, recipient.id) do
          now = Map.get(attrs, :published) |> parse_published() || DateTime.utc_now()
          message_attrs = %{"content" => plaintext}

          with {:ok, encrypted_attrs} <-
                 encrypt_message_attrs(conv.id, sender.id, message_attrs) do
            encrypted_attrs =
              encrypted_attrs
              |> Map.put("ap_id", remote_ap_id)

            case do_insert_remote_message(conv.id, sender.id, encrypted_attrs, now) do
              {:ok, message} ->
                {:ok, decrypt_message(message)}

              other ->
                other
            end
          end
        end
    end
  end

  defp prior_message_ap_id(conversation_id, current_message_id) do
    Message
    |> where(
      [m],
      m.conversation_id == ^conversation_id and m.id != ^current_message_id and
        is_nil(m.deleted_at) and not is_nil(m.ap_id)
    )
    |> order_by([m], desc: m.created_at)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> nil
      msg -> msg.ap_id
    end
  end

  defp parse_published(nil), do: nil

  defp parse_published(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      # Our `messages.created_at` column is `utc_datetime_usec`; Mastodon's
      # `published` is second-precision, so pad microseconds explicitly
      # rather than letting Ecto reject the value.
      {:ok, dt, _offset} -> %{dt | microsecond: {0, 6}}
      _ -> nil
    end
  end

  defp parse_published(_), do: nil

  # Insert path for remote DMs. Same shape as `do_send_message` but
  # skips the delivery-status rows (they track outbound fan-out — an
  # inbound message has no recipients to track) and the publisher
  # task (the sender is remote).
  defp do_insert_remote_message(conversation_id, _sender_id, message_attrs, now) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(
      :message,
      Message.encrypted_changeset(%Message{created_at: now}, message_attrs)
    )
    |> Ecto.Multi.run(:bump_conversation, fn repo, _changes ->
      Conversation
      |> where([c], c.id == ^conversation_id)
      |> repo.update_all(set: [updated_at: now])

      {:ok, :bumped}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{message: message}} ->
        broadcast_new_message(message)
        {:ok, message}

      {:error, :message, changeset, _changes} ->
        {:error, changeset}

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  # Dispatches to the right activity builder per recipient software.
  # The compose-time `check_peer_supports_dm` gate means chat-incapable
  # peers shouldn't land here, but a peer could flip capability after
  # a conversation was created — in that case we log + fall back to a
  # direct-visibility Note so the message still reaches them somehow.
  defp build_dm_activity(sender, recipient, message, plaintext) do
    if Hybridsocial.Federation.NodeInfo.chat_capable?(recipient.ap_actor_url) do
      build_chat_message_create(sender, recipient, message, plaintext)
    else
      Logger.warning(
        "DM target #{recipient.ap_actor_url} is not chat-capable; emitting Note fallback"
      )

      build_direct_create(sender, recipient, message, plaintext)
    end
  end

  # Pleroma/Akkoma native one-on-one DM primitive. Distinct from
  # Note: it has no public addressing (ever), no `tag` array, no
  # conversation URI (they pair by sender↔recipient internally),
  # and `content` is plaintext — the peer does its own rendering.
  # The `ChatMessage` term must be declared in the `@context` or
  # strict JSON-LD parsers drop the type; Pleroma itself publishes
  # this mapping so we mirror what they emit.
  defp build_chat_message_create(sender, recipient, message, plaintext) do
    base = HybridsocialWeb.Endpoint.url()
    sender_url = "#{base}/actors/#{sender.id}"
    chat_id = "#{base}/dm/#{message.id}"
    activity_id = "#{base}/activities/#{sender.id}/create-chat/#{message.id}"
    published = message.created_at || DateTime.utc_now()

    chat = %{
      "type" => "ChatMessage",
      "id" => chat_id,
      "attributedTo" => sender_url,
      "to" => [recipient.ap_actor_url],
      "content" => plaintext,
      "published" => DateTime.to_iso8601(published)
    }

    %{
      "@context" => [
        "https://www.w3.org/ns/activitystreams",
        "https://w3id.org/security/v1",
        %{"ChatMessage" => "http://litepub.social/ns#ChatMessage"}
      ],
      "id" => activity_id,
      "type" => "Create",
      "actor" => sender_url,
      "published" => DateTime.to_iso8601(published),
      "to" => [recipient.ap_actor_url],
      "object" => chat
    }
  end

  defp build_direct_create(sender, recipient, message, plaintext) do
    base = HybridsocialWeb.Endpoint.url()
    sender_url = "#{base}/actors/#{sender.id}"
    # Use `/dm/:id` rather than `/messages/:id` — the latter collides
    # with the SvelteKit DM conversation route, so when Mastodon
    # links to "see replies on the origin instance" the frontend tries to
    # load the message UUID as a conversation and renders blank.
    note_id = "#{base}/dm/#{message.id}"
    activity_id = "#{base}/activities/#{sender.id}/create-dm/#{message.id}"
    published = message.created_at || DateTime.utc_now()

    # Stable, non-dereferenceable thread key. Mastodon uses the
    # `conversation` / `context` URI (as opaque string) to group
    # statuses into a single thread in the DM UI. Without it, every
    # message we send shows up as its own thread in "Private mentions".
    %URI{host: host} = URI.parse(base)
    thread_uri = "tag:#{host},2026:objectId=#{message.conversation_id}:objectType=Conversation"

    mention = %{
      "type" => "Mention",
      "href" => recipient.ap_actor_url,
      "name" => "@#{recipient.handle}"
    }

    # Chain this message to the most recent prior message in the
    # conversation. Mastodon's private-mentions view groups by the
    # `conversation` URI, but the actual thread tree is built from
    # `inReplyTo` — without the chain, each DM renders as its own
    # standalone thread when the user clicks in.
    in_reply_to = prior_message_ap_id(message.conversation_id, message.id)

    note = %{
      "type" => "Note",
      "id" => note_id,
      "attributedTo" => sender_url,
      "content" => plaintext,
      "published" => DateTime.to_iso8601(published),
      "to" => [recipient.ap_actor_url],
      "cc" => [],
      "tag" => [mention],
      "inReplyTo" => in_reply_to,
      "conversation" => thread_uri,
      "context" => thread_uri,
      # Mastodon uses this extension to flag messages as DMs in the
      # UI — without it the recipient sees the note as a mention in
      # their notifications rather than in their DMs inbox.
      "directMessage" => true
    }

    %{
      "@context" => [
        "https://www.w3.org/ns/activitystreams",
        "https://w3id.org/security/v1"
      ],
      "id" => activity_id,
      "type" => "Create",
      "actor" => sender_url,
      "published" => DateTime.to_iso8601(published),
      "to" => [recipient.ap_actor_url],
      "cc" => [],
      "object" => note
    }
  end

  defp encrypt_message_attrs(conversation_id, sender_id, attrs) do
    plaintext = attrs["content"] || ""

    case Hybridsocial.Messaging.Crypto.encrypt(plaintext, conversation_id) do
      {:ok, ciphertext, nonce, version} ->
        encrypted =
          attrs
          |> Map.delete("content")
          |> Map.put("conversation_id", conversation_id)
          |> Map.put("sender_id", sender_id)
          |> Map.put("ciphertext", ciphertext)
          |> Map.put("nonce", nonce)
          |> Map.put("encryption_version", version)

        {:ok, encrypted}

      {:error, reason} ->
        {:error, {:encryption_failed, reason}}
    end
  end

  defp do_send_message(conversation_id, sender_id, message_attrs, now) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(
      :message,
      Message.encrypted_changeset(%Message{created_at: now}, message_attrs)
    )
    |> Ecto.Multi.run(:update_conversation, fn repo, %{message: _msg} ->
      Conversation
      |> where([c], c.id == ^conversation_id)
      |> repo.update_all(set: [updated_at: now])

      {:ok, :updated}
    end)
    |> Ecto.Multi.run(:delivery_statuses, fn repo, %{message: msg} ->
      recipients =
        Participant
        |> where(
          [p],
          p.conversation_id == ^conversation_id and p.identity_id != ^sender_id and
            is_nil(p.left_at)
        )
        |> select([p], p.identity_id)
        |> repo.all()

      statuses =
        Enum.map(recipients, fn recipient_id ->
          %DeliveryStatus{}
          |> DeliveryStatus.changeset(%{
            message_id: msg.id,
            recipient_id: recipient_id,
            status: "sent"
          })
          |> repo.insert!()
        end)

      {:ok, statuses}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{message: message}} ->
        broadcast_new_message(message)
        {:ok, decrypt_message(message)}

      {:error, :message, changeset, _changes} ->
        {:error, changeset}

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  @doc """
  Translate a message's text into `target_lang` for a conversation participant.

  Any participant (not just the sender) may translate a message they can read.
  Only plaintext bodies can be translated — an end-to-end encrypted message has
  no server-side plaintext, so it returns `{:error, :no_content}`. Delegates the
  actual translation to `Hybridsocial.Content.Translation`, so it inherits the
  admin-configured backend and the disabled-by-default behaviour.
  """
  def translate_message(message_id, identity_id, target_lang) do
    case Repo.get(Message, message_id) do
      nil ->
        {:error, :not_found}

      %Message{deleted_at: deleted_at} when not is_nil(deleted_at) ->
        {:error, :not_found}

      %Message{} = message ->
        cond do
          not participant?(message.conversation_id, identity_id) ->
            {:error, :forbidden}

          is_nil(message.content) or message.content == "" ->
            {:error, :no_content}

          true ->
            Hybridsocial.Content.Translation.translate(message.content, target_lang)
        end
    end
  end

  @doc "Edit a message. Only the sender can edit."
  def edit_message(message_id, sender_id, new_content) do
    case Repo.get(Message, message_id) do
      nil ->
        {:error, :not_found}

      %Message{sender_id: ^sender_id, deleted_at: nil} = message ->
        if within_edit_window?(message) do
          edit_encrypted(message, new_content)
        else
          {:error, :edit_window_expired}
        end

      %Message{deleted_at: deleted_at} when not is_nil(deleted_at) ->
        {:error, :not_found}

      %Message{} ->
        {:error, :forbidden}
    end
  end

  # Senders may edit their own DMs for a brief grace period after
  # send (default 5 min). After that the bubble locks down — anyone
  # remembering the original wording is then guaranteed to still be
  # looking at the same bytes.
  defp within_edit_window?(%Message{created_at: created_at}) do
    seconds = Hybridsocial.Config.get("dm_edit_window_seconds", 300)
    cutoff = DateTime.add(created_at, seconds, :second)
    DateTime.compare(DateTime.utc_now(), cutoff) == :lt
  end

  defp edit_encrypted(message, new_content) do
    case Hybridsocial.Messaging.Crypto.encrypt(new_content, message.conversation_id) do
      {:ok, ciphertext, nonce, version} ->
        case message
             |> Message.edit_encrypted_changeset(%{
               ciphertext: ciphertext,
               nonce: nonce,
               encryption_version: version,
               edited_at: DateTime.utc_now()
             })
             |> Repo.update() do
          {:ok, updated} -> {:ok, decrypt_message(updated)}
          other -> other
        end

      {:error, reason} ->
        {:error, {:encryption_failed, reason}}
    end
  end

  @doc "Soft-delete a message. Only the sender can delete."
  def delete_message(message_id, sender_id) do
    case Repo.get(Message, message_id) do
      nil ->
        {:error, :not_found}

      %Message{sender_id: ^sender_id, deleted_at: nil} = message ->
        message
        |> Message.delete_changeset()
        |> Repo.update()

      %Message{deleted_at: deleted_at} when not is_nil(deleted_at) ->
        {:error, :not_found}

      %Message{} ->
        {:error, :forbidden}
    end
  end

  @doc "Get paginated messages for a conversation. Verifies participant."
  def get_messages(conversation_id, identity_id, opts \\ []) do
    if participant?(conversation_id, identity_id) do
      limit = Keyword.get(opts, :limit, 50)
      offset = Keyword.get(opts, :offset, 0)

      messages =
        Message
        |> where([m], m.conversation_id == ^conversation_id and is_nil(m.deleted_at))
        |> order_by([m], desc: m.created_at)
        |> limit(^limit)
        |> offset(^offset)
        |> preload([:sender])
        |> Repo.all()
        |> Enum.map(&decrypt_message/1)

      {:ok, messages}
    else
      {:error, :not_found}
    end
  end

  @doc """
  Decrypts a message in-place: populates `content` with the plaintext for
  the caller, leaving ciphertext/nonce intact on the struct. Version 0
  rows pass through untouched. Decryption failures leave `content` nil
  and tag the struct with an error atom (never crashes a list fetch).
  """
  def decrypt_message(%Message{encryption_version: 0} = message), do: message

  def decrypt_message(%Message{encryption_version: v} = message) when v > 0 do
    case Hybridsocial.Messaging.Crypto.decrypt(
           message.ciphertext,
           message.nonce,
           message.conversation_id,
           message.encryption_version
         ) do
      {:ok, plaintext} -> %{message | content: plaintext}
      {:error, _reason} -> %{message | content: nil}
    end
  end

  def decrypt_message(other), do: other

  @doc "Mark all messages in a conversation as read for an identity."
  def mark_read(conversation_id, identity_id) do
    latest_message =
      Message
      |> where([m], m.conversation_id == ^conversation_id and is_nil(m.deleted_at))
      |> order_by([m], desc: m.created_at)
      |> limit(1)
      |> Repo.one()

    case latest_message do
      nil ->
        {:ok, :no_messages}

      message ->
        Participant
        |> where(
          [p],
          p.conversation_id == ^conversation_id and p.identity_id == ^identity_id and
            is_nil(p.left_at)
        )
        |> Repo.one()
        |> case do
          nil ->
            {:error, :not_found}

          participant ->
            result =
              participant
              |> Ecto.Changeset.change(last_read_message_id: message.id)
              |> Repo.update()

            # Broadcast read receipt
            broadcast_conversation_event(conversation_id, :read, %{
              identity_id: identity_id,
              last_read_message_id: message.id
            })

            # Update delivery statuses to 'read'
            DeliveryStatus
            |> where([d], d.recipient_id == ^identity_id)
            |> join(:inner, [d], m in Message,
              on: d.message_id == m.id and m.conversation_id == ^conversation_id
            )
            |> where([d], d.status != "read")
            |> Repo.update_all(set: [status: "read", updated_at: DateTime.utc_now()])

            result
        end
    end
  end

  @doc """
  Bump the delivery status of `message_id` for `recipient_id` to "delivered"
  if it was "sent". Idempotent — never downgrades a "read" row, never
  errors if the row doesn't exist (the sender's own messages have no row
  for themselves; remote-imported messages won't either). Broadcasts
  `chat.delivered` back to the sender so their ticks can flip to two grey.
  """
  def mark_delivered(message_id, recipient_id) do
    now = DateTime.utc_now()

    {updated_count, _} =
      DeliveryStatus
      |> where(
        [d],
        d.message_id == ^message_id and d.recipient_id == ^recipient_id and d.status == "sent"
      )
      |> Repo.update_all(set: [status: "delivered", updated_at: now])

    if updated_count > 0 do
      broadcast_message_event(message_id, :delivered, %{
        message_id: message_id,
        recipient_id: recipient_id,
        status: "delivered"
      })
    end

    {:ok, updated_count}
  end

  @doc """
  The lowest delivery state across all recipients of a message. Returns
  one of "sent" / "delivered" / "read". When no rows exist (e.g. an
  outbound message with no local recipients yet) returns "sent" — the
  message was at least accepted by our server.
  """
  def lowest_delivery_status(message_id) do
    statuses =
      DeliveryStatus
      |> where([d], d.message_id == ^message_id)
      |> select([d], d.status)
      |> Repo.all()

    cond do
      statuses == [] -> "sent"
      Enum.any?(statuses, &(&1 == "sent")) -> "sent"
      Enum.any?(statuses, &(&1 == "delivered")) -> "delivered"
      true -> "read"
    end
  end

  @doc "Count unread messages in a conversation for an identity."
  def unread_count(conversation_id, identity_id) do
    participant =
      Participant
      |> where(
        [p],
        p.conversation_id == ^conversation_id and p.identity_id == ^identity_id and
          is_nil(p.left_at)
      )
      |> Repo.one()

    case participant do
      nil ->
        {:error, :not_found}

      %Participant{last_read_message_id: nil} ->
        count =
          Message
          |> where([m], m.conversation_id == ^conversation_id and is_nil(m.deleted_at))
          |> Repo.aggregate(:count)

        {:ok, count}

      %Participant{last_read_message_id: last_read_id} ->
        last_read = Repo.get(Message, last_read_id)

        case last_read do
          nil ->
            count =
              Message
              |> where([m], m.conversation_id == ^conversation_id and is_nil(m.deleted_at))
              |> Repo.aggregate(:count)

            {:ok, count}

          %Message{created_at: last_read_at} ->
            count =
              Message
              |> where(
                [m],
                m.conversation_id == ^conversation_id and
                  is_nil(m.deleted_at) and
                  m.created_at > ^last_read_at
              )
              |> Repo.aggregate(:count)

            {:ok, count}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # DM Preferences
  # ---------------------------------------------------------------------------

  @doc "Get DM preferences for an identity, returning defaults if not set."
  def get_dm_preferences(identity_id) do
    case Repo.get(DmPreference, identity_id) do
      nil ->
        {:ok,
         %DmPreference{
           identity_id: identity_id,
           allow_dms_from: "everyone",
           allow_group_dms: false
         }}

      pref ->
        {:ok, pref}
    end
  end

  @doc "Update DM preferences for an identity."
  def update_dm_preferences(identity_id, attrs) do
    case Repo.get(DmPreference, identity_id) do
      nil ->
        %DmPreference{identity_id: identity_id}
        |> DmPreference.changeset(attrs)
        |> Repo.insert()

      pref ->
        pref
        |> DmPreference.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Check if sender is allowed to DM recipient based on preferences and blocks.

  Preference rules:
  - everyone: always allowed
  - followers: recipient follows sender
  - mutual_followers: both follow each other
  - nobody: never allowed

  Also checks blocks in both directions.
  """
  def can_dm?(sender_id, recipient_id) do
    # Check blocks in both directions
    if Social.blocked?(sender_id, recipient_id) or Social.blocked?(recipient_id, sender_id) do
      false
    else
      pref = Repo.get(DmPreference, recipient_id)
      allow_from = if pref, do: pref.allow_dms_from, else: "everyone"

      case allow_from do
        "everyone" ->
          true

        "followers" ->
          Social.following?(recipient_id, sender_id)

        "mutual_followers" ->
          Social.following?(recipient_id, sender_id) and
            Social.following?(sender_id, recipient_id)

        "nobody" ->
          false
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp participant?(conversation_id, identity_id) do
    Participant
    |> where(
      [p],
      p.conversation_id == ^conversation_id and p.identity_id == ^identity_id and
        is_nil(p.left_at)
    )
    |> Repo.exists?()
  end

  # ---------------------------------------------------------------------------
  # Chat Acceptance
  # ---------------------------------------------------------------------------

  @doc "Accept a pending conversation."
  def accept_conversation(conversation_id, identity_id) do
    with {:ok, conv} <- get_conversation(conversation_id, identity_id) do
      conv
      |> Conversation.changeset(%{accepted: true})
      |> Repo.update()
    end
  end

  @doc "Decline (delete) a pending conversation."
  def decline_conversation(conversation_id, identity_id) do
    with {:ok, conv} <- get_conversation(conversation_id, identity_id) do
      Repo.delete(conv)
    end
  end

  # ---------------------------------------------------------------------------
  # Message Reactions
  # ---------------------------------------------------------------------------

  @doc """
  Add an emoji reaction to a message.

  Returns `{:error, :premium_required}` when `emoji` is in the
  admin-curated premium reaction catalog and the caller's tier
  doesn't include `custom_emoji` (free / verified_starter).
  """
  def react_to_message(message_id, identity_id, emoji) do
    with :ok <- check_reaction_tier(emoji, identity_id) do
      do_react_single(message_id, identity_id, emoji)
    end
  end

  # One reaction per user per message. Clicking the same emoji again
  # removes it (toggle). Clicking a different emoji swaps the previous
  # one for the new one. The controller returns the action so the
  # client can update its local view without refetching.
  defp do_react_single(message_id, identity_id, emoji) do
    existing =
      Repo.get_by(MessageReaction, message_id: message_id, identity_id: identity_id)

    cond do
      is_nil(existing) ->
        case insert_reaction(message_id, identity_id, emoji) do
          {:ok, reaction} ->
            broadcast_reaction(message_id, :reaction_added, identity_id, emoji)
            {:ok, :added, reaction}

          err ->
            err
        end

      existing.emoji == emoji ->
        case Repo.delete(existing) do
          {:ok, _} ->
            broadcast_reaction(message_id, :reaction_removed, identity_id, emoji)
            {:ok, :removed, emoji}

          err ->
            err
        end

      true ->
        previous = existing.emoji

        case Repo.delete(existing) do
          {:ok, _} ->
            case insert_reaction(message_id, identity_id, emoji) do
              {:ok, reaction} ->
                broadcast_reaction(message_id, :reaction_removed, identity_id, previous)
                broadcast_reaction(message_id, :reaction_added, identity_id, emoji)
                {:ok, :swapped, reaction, previous}

              err ->
                err
            end

          err ->
            err
        end
    end
  end

  defp insert_reaction(message_id, identity_id, emoji) do
    %MessageReaction{}
    |> MessageReaction.changeset(%{
      message_id: message_id,
      identity_id: identity_id,
      emoji: emoji
    })
    |> Repo.insert()
  end

  defp broadcast_reaction(message_id, event, identity_id, emoji) do
    # Include the aggregated reactions snapshot so the client can
    # render the new state directly off the broadcast (otherwise the
    # delta handler has no data to apply).
    reactions = get_message_reactions(message_id)

    broadcast_message_event(message_id, event, %{
      message_id: message_id,
      identity_id: identity_id,
      emoji: emoji,
      reactions: reactions
    })
  end

  defp check_reaction_tier(emoji, identity_id) do
    cond do
      Hybridsocial.Reactions.default_reaction?(emoji) ->
        :ok

      Hybridsocial.Reactions.premium_reaction?(emoji) ->
        identity = Hybridsocial.Repo.get(Hybridsocial.Accounts.Identity, identity_id)

        if identity && Hybridsocial.Premium.TierLimits.limit(identity, :custom_emoji) do
          :ok
        else
          {:error, :premium_required}
        end

      true ->
        # Unknown emoji — let the existing changeset rules decide.
        # Don't block here so legitimate future expansions of the
        # reaction set keep working.
        :ok
    end
  end

  @doc "Remove an emoji reaction from a message."
  def unreact_to_message(message_id, identity_id, emoji) do
    case Repo.get_by(MessageReaction,
           message_id: message_id,
           identity_id: identity_id,
           emoji: emoji
         ) do
      nil ->
        {:error, :not_found}

      reaction ->
        case Repo.delete(reaction) do
          {:ok, _} ->
            broadcast_reaction(message_id, :reaction_removed, identity_id, emoji)
            :ok

          error ->
            error
        end
    end
  end

  @doc "Get reactions for a message."
  def get_message_reactions(message_id) do
    MessageReaction
    |> where([r], r.message_id == ^message_id)
    |> preload(:identity)
    |> Repo.all()
    |> Enum.group_by(& &1.emoji)
    |> Enum.map(fn {emoji, reactions} ->
      %{
        emoji: emoji,
        count: length(reactions),
        accounts:
          Enum.map(reactions, fn r ->
            %{id: r.identity.id, handle: r.identity.handle, display_name: r.identity.display_name}
          end)
      }
    end)
  end

  # ---------------------------------------------------------------------------
  # Read Receipts Broadcasting
  # ---------------------------------------------------------------------------

  @doc "Mark as read and broadcast the read receipt."
  def mark_read_with_broadcast(conversation_id, identity_id) do
    result = mark_read(conversation_id, identity_id)
    broadcast_conversation_event(conversation_id, :read, %{identity_id: identity_id})
    result
  end

  @doc """
  Broadcast a transient `chat.typing` signal to the conversation's
  participants (the sender is filtered out client-side). Only members can
  emit one. Fire-and-forget — nothing is persisted.
  """
  def broadcast_typing(conversation_id, identity_id) do
    member? =
      Participant
      |> where(
        [p],
        p.conversation_id == ^conversation_id and p.identity_id == ^identity_id and
          is_nil(p.left_at)
      )
      |> Repo.exists?()

    if member? do
      broadcast_conversation_event(conversation_id, :typing, %{identity_id: identity_id})
      :ok
    else
      {:error, :not_found}
    end
  end

  # ---------------------------------------------------------------------------
  # PubSub Broadcasting
  # ---------------------------------------------------------------------------

  defp broadcast_message_event(message_id, event, payload) do
    # Get conversation_id from message
    case Repo.get(Message, message_id) do
      nil ->
        :ok

      message ->
        broadcast_conversation_event(message.conversation_id, event, payload)
    end
  end

  defp broadcast_conversation_event(conversation_id, event, payload) do
    # Broadcast to all participants in the SSE-compatible format
    participants =
      Participant
      |> where([p], p.conversation_id == ^conversation_id and is_nil(p.left_at))
      |> select([p], p.identity_id)
      |> Repo.all()

    event_name = "chat.#{event}"
    full_payload = Map.put(payload, :conversation_id, conversation_id)

    for pid <- participants do
      Phoenix.PubSub.broadcast(
        Hybridsocial.PubSub,
        "user:#{pid}",
        %{event: event_name, payload: full_payload}
      )
    end
  end

  @doc "Broadcast a new message to all conversation participants."
  def broadcast_new_message(message) do
    message = message |> Repo.preload([:sender, :media]) |> decrypt_message()

    media_attachments =
      case message.media do
        %Hybridsocial.Media.MediaFile{} = m ->
          [HybridsocialWeb.Serializers.PostSerializer.serialize_media_attachment(m)]

        _ ->
          []
      end

    broadcast_conversation_event(message.conversation_id, :new_message, %{
      id: message.id,
      conversation_id: message.conversation_id,
      content: message.content,
      content_type: message.content_type,
      reply_to_id: message.reply_to_id,
      sender: HybridsocialWeb.Helpers.Account.serialize_summary(message.sender),
      media_id: message.media_id,
      media_attachments: media_attachments,
      reactions: [],
      delivery_status: "sent",
      created_at: message.created_at
    })
  end
end
