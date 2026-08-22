defmodule HybridsocialWeb.Api.V1.ConversationController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Messaging
  alias Hybridsocial.Media.MediaFile
  alias Hybridsocial.Repo
  alias HybridsocialWeb.Serializers.PostSerializer
  import HybridsocialWeb.Helpers.Pagination, only: [clamp_limit: 1]

  # GET /api/v1/conversations
  def index(conn, params) do
    identity = conn.assigns.current_identity

    opts = [
      limit: clamp_limit(params["limit"]),
      offset: parse_int(params["offset"], 0)
    ]

    conversations = Messaging.list_conversations(identity.id, opts)
    json(conn, Enum.map(conversations, &serialize_conversation/1))
  end

  # GET /api/v1/conversations/:id
  def show(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity

    case Messaging.get_conversation(id, identity.id) do
      {:ok, conversation} ->
        json(conn, serialize_conversation(conversation))

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "conversation.not_found"})
    end
  end

  # POST /api/v1/conversations
  def create(conn, params) do
    identity = conn.assigns.current_identity
    recipient_ids = Map.get(params, "recipient_ids", [])

    result =
      case recipient_ids do
        [recipient_id] ->
          Messaging.find_or_create_direct(identity.id, recipient_id)

        ids when is_list(ids) and length(ids) > 1 ->
          Messaging.create_group_dm(identity.id, ids)

        _ ->
          {:error, :invalid_recipients}
      end

    case result do
      {:ok, conversation} ->
        conversation = Hybridsocial.Repo.preload(conversation, [:participants])

        conn
        |> put_status(:created)
        |> json(serialize_conversation(conversation))

      {:error, :dm_not_allowed} ->
        conn |> put_status(:forbidden) |> json(%{error: "dm.not_allowed"})

      {:error, :dm_not_supported, info} ->
        # Peer software doesn't speak ChatMessage. The frontend will
        # catch this and silently compose a direct-visibility post
        # with the recipient mentioned instead.
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          error: "dm.not_supported_by_peer",
          fallback: "direct_post",
          recipient: info
        })

      {:error, :cannot_message_self} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "dm.cannot_message_self"})

      {:error, :insufficient_participants} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "dm.insufficient_participants"})

      {:error, :invalid_recipients} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "dm.invalid_recipients"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  # POST /api/v1/conversations/:id/messages
  def send_message(conn, %{"id" => conversation_id} = params) do
    identity = conn.assigns.current_identity

    attrs = Map.take(params, ["content", "content_type", "media_id", "reply_to_id"])

    # The frontend sends `media_ids` (array) since the post composer uses
    # multi-attachment posts. DMs currently only support a single media
    # per message, so promote the first item if present and the caller
    # didn't already pass `media_id`.
    attrs =
      case Map.get(params, "media_ids") do
        [first | _] when is_binary(first) and not is_map_key(attrs, "media_id") ->
          Map.put(attrs, "media_id", first)

        _ ->
          attrs
      end

    case Messaging.send_message(conversation_id, identity.id, attrs) do
      {:ok, message} ->
        message = Hybridsocial.Repo.preload(message, [:sender, :media])

        conn
        |> put_status(:created)
        |> json(serialize_message(message, identity.id))

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "conversation.not_found"})

      {:error, {:encryption_failed, reason}} ->
        # DMs are encrypted at rest. If the master key isn't
        # configured we can't store anything, so surface a clear
        # operator-facing error instead of a generic 500.
        conn
        |> put_status(:service_unavailable)
        |> json(%{
          error: "dm.encryption_unavailable",
          detail: to_string(reason)
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "message.failed", detail: inspect(reason)})
    end
  end

  # GET /api/v1/conversations/:id/messages
  def messages(conn, %{"id" => conversation_id} = params) do
    identity = conn.assigns.current_identity

    opts = [
      limit: clamp_limit(params["limit"]),
      offset: parse_int(params["offset"], 0)
    ]

    case Messaging.get_messages(conversation_id, identity.id, opts) do
      {:ok, messages} ->
        messages = Repo.preload(messages, [:media])
        json(conn, Enum.map(messages, &serialize_message(&1, identity.id)))

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "conversation.not_found"})
    end
  end

  # PUT /api/v1/conversations/:id/messages/:mid
  def translate_message(conn, %{"id" => _conversation_id, "mid" => message_id} = params) do
    identity = conn.assigns.current_identity
    target_lang = params["target_lang"] || "en"

    case Messaging.translate_message(message_id, identity.id, target_lang) do
      {:ok, translated} ->
        json(conn, %{
          content: translated,
          provider: Hybridsocial.Config.get("translation_backend", "none")
        })

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "message.not_found"})

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "message.forbidden"})

      {:error, :no_content} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "message.no_content"})

      {:error, :translation_disabled} ->
        conn |> put_status(:service_unavailable) |> json(%{error: "translation.disabled"})

      {:error, reason} ->
        conn
        |> put_status(:bad_gateway)
        |> json(%{error: "translation.failed", detail: inspect(reason)})
    end
  end

  def edit_message(conn, %{"id" => _conversation_id, "mid" => message_id} = params) do
    identity = conn.assigns.current_identity
    new_content = Map.get(params, "content", "")

    case Messaging.edit_message(message_id, identity.id, new_content) do
      {:ok, message} ->
        message = Hybridsocial.Repo.preload(message, [:sender, :media])
        json(conn, serialize_message(message, identity.id))

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "message.not_found"})

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "message.forbidden"})

      {:error, :edit_window_expired} ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          error: "message.edit_window_expired",
          message: "This message can no longer be edited. The edit window has closed."
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  # DELETE /api/v1/conversations/:id
  def delete_conversation(conn, %{"id" => conversation_id}) do
    identity = conn.assigns.current_identity

    case Messaging.delete_conversation(conversation_id, identity.id) do
      {:ok, _participant} ->
        json(conn, %{message: "conversation.deleted"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "conversation.not_found"})
    end
  end

  # DELETE /api/v1/conversations/:id/messages/:mid
  def delete_message(conn, %{"id" => _conversation_id, "mid" => message_id}) do
    identity = conn.assigns.current_identity

    case Messaging.delete_message(message_id, identity.id) do
      {:ok, _message} ->
        json(conn, %{message: "message.deleted"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "message.not_found"})

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "message.forbidden"})
    end
  end

  # POST /api/v1/conversations/:id/read
  def mark_read(conn, %{"id" => conversation_id}) do
    identity = conn.assigns.current_identity

    case Messaging.mark_read(conversation_id, identity.id) do
      {:ok, _} ->
        json(conn, %{message: "conversation.marked_read"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "conversation.not_found"})
    end
  end

  # POST /api/v1/conversations/:id/typing — fire-and-forget typing ping.
  def typing(conn, %{"id" => conversation_id}) do
    identity = conn.assigns.current_identity

    case Messaging.broadcast_typing(conversation_id, identity.id) do
      :ok ->
        send_resp(conn, :no_content, "")

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "conversation.not_found"})
    end
  end

  # PATCH /api/v1/conversations/:id/settings
  def update_settings(conn, %{"id" => conversation_id} = params) do
    identity = conn.assigns.current_identity

    result =
      case params["notifications_enabled"] do
        false -> Messaging.mute_conversation(conversation_id, identity.id)
        true -> Messaging.unmute_conversation(conversation_id, identity.id)
        _ -> {:error, :invalid_settings}
      end

    case result do
      {:ok, participant} ->
        json(conn, %{
          conversation_id: conversation_id,
          notifications_enabled: participant.notifications_enabled
        })

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "conversation.not_found"})

      {:error, :invalid_settings} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "settings.invalid"})
    end
  end

  # GET /api/v1/dm_preferences
  def dm_preferences(conn, _params) do
    identity = conn.assigns.current_identity

    case Messaging.get_dm_preferences(identity.id) do
      {:ok, pref} ->
        json(conn, serialize_dm_preference(pref))
    end
  end

  # PATCH /api/v1/dm_preferences
  def update_dm_preferences(conn, params) do
    identity = conn.assigns.current_identity
    attrs = Map.take(params, ["allow_dms_from", "allow_group_dms"])

    case Messaging.update_dm_preferences(identity.id, attrs) do
      {:ok, pref} ->
        json(conn, serialize_dm_preference(pref))

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  # ---------------------------------------------------------------------------
  # Serialization
  # ---------------------------------------------------------------------------

  defp serialize_conversation(conversation) do
    participants =
      case conversation.participants do
        %Ecto.Association.NotLoaded{} -> []
        participants -> Enum.map(participants, &serialize_participant/1)
      end

    # Three explicit encryption states the frontend renders as three
    # different icons. Don't conflate them into a single boolean.
    #   - "at_rest"   (amber lock): local conversation, ciphertext in DB,
    #                  server holds the master key — can decrypt if compelled.
    #   - "federated" (no lock): at least one remote participant. Our side
    #                  is still encrypted at rest, but the remote server
    #                  received plaintext in the AP envelope.
    #   - "e2ee"      (green lock): reserved for future end-to-end. Never
    #                  emitted today.
    encryption_status = if conversation.is_local, do: "at_rest", else: "federated"

    %{
      id: conversation.id,
      type: conversation.type,
      accepted: conversation.accepted,
      is_local: conversation.is_local,
      encryption_status: encryption_status,
      # Legacy field kept for the old clients; deprecated by encryption_status.
      is_encrypted: conversation.is_local == true,
      created_by_id: conversation.created_by_id,
      participants: participants,
      last_message: serialize_last_message(Map.get(conversation, :last_message)),
      unread_count: Map.get(conversation, :unread_count) || 0,
      created_at: conversation.inserted_at,
      updated_at: conversation.updated_at
    }
  end

  defp serialize_last_message(nil), do: nil

  defp serialize_last_message(%Hybridsocial.Messaging.Message{} = message) do
    %{
      id: message.id,
      content: message.content,
      content_type: message.content_type,
      sender_id: message.sender_id,
      created_at: message.created_at
    }
  end

  defp serialize_participant(participant) do
    identity =
      case participant do
        %{identity: %Hybridsocial.Accounts.Identity{} = id} ->
          id

        _ ->
          # Include soft-deleted so a deleted participant still renders as
          # "Deleted User" rather than vanishing from the thread.
          Hybridsocial.Accounts.get_identity_including_deleted(participant.identity_id)
      end

    summary = HybridsocialWeb.Helpers.Account.serialize_summary(identity) || %{}

    %{
      id: participant.id,
      identity_id: participant.identity_id,
      handle: Map.get(summary, :handle),
      acct: Map.get(summary, :acct),
      display_name: Map.get(summary, :display_name),
      avatar_url: Map.get(summary, :avatar_url),
      joined_at: participant.joined_at,
      notifications_enabled: participant.notifications_enabled,
      left_at: participant.left_at
    }
  end

  defp serialize_message(message, viewer_id) do
    sender =
      case message.sender do
        %Hybridsocial.Accounts.Identity{} = identity ->
          HybridsocialWeb.Helpers.Account.serialize_summary(identity)

        _ ->
          nil
      end

    # Get reactions for this message
    reactions = Hybridsocial.Messaging.get_message_reactions(message.id)

    # Single-attachment DMs surfaced as a one-element array so the
    # frontend can render them with the same component it uses for
    # multi-attachment posts. When the join-table refactor lands this
    # turns into a real list without a serializer change.
    media_attachments =
      case message.media do
        %MediaFile{} = m -> [PostSerializer.serialize_media_attachment(m)]
        _ -> []
      end

    # Read receipts: tell the sender (only) the lowest delivery state
    # across all recipients of this message. For a 1:1 DM that's the
    # single recipient's state; for a group it's the slowest reader.
    # Hidden from non-senders so the UI never accidentally shows ticks
    # on someone else's message.
    delivery_status =
      if viewer_id && sender && sender[:id] == viewer_id do
        Messaging.lowest_delivery_status(message.id)
      end

    %{
      id: message.id,
      conversation_id: message.conversation_id,
      content: message.content,
      content_type: message.content_type,
      sender: sender,
      media_id: message.media_id,
      media_attachments: media_attachments,
      reply_to_id: message.reply_to_id,
      reactions: reactions,
      delivery_status: delivery_status,
      edited_at: message.edited_at,
      created_at: message.created_at
    }
  end

  defp serialize_dm_preference(pref) do
    %{
      identity_id: pref.identity_id,
      allow_dms_from: pref.allow_dms_from,
      allow_group_dms: pref.allow_group_dms
    }
  end

  defp parse_int(nil, default), do: default

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_int(val, _default) when is_integer(val), do: val

  # POST /api/v1/conversations/:id/accept
  def accept(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity

    case Messaging.accept_conversation(id, identity.id) do
      {:ok, conv} ->
        conv = Hybridsocial.Repo.preload(conv, participants: :identity)
        json(conn, serialize_conversation(conv))

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "conversation.not_found"})
    end
  end

  # DELETE /api/v1/conversations/:id/decline
  def decline(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity

    case Messaging.decline_conversation(id, identity.id) do
      {:ok, _} ->
        json(conn, %{status: "ok"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "conversation.not_found"})
    end
  end

  # POST /api/v1/conversations/:id/messages/:mid/reactions
  #
  # One reaction per user per message. The controller returns `action`
  # so the client can reflect the outcome without refetching:
  #   * "added"   — no prior reaction, new one stored
  #   * "removed" — same emoji clicked again, toggled off
  #   * "swapped" — different emoji replaces the previous one
  # The aggregated `reactions` list mirrors the payload that gets
  # broadcast to other participants over SSE.
  def add_reaction(conn, %{"id" => _conv_id, "mid" => message_id, "emoji" => emoji}) do
    identity = conn.assigns.current_identity

    case Messaging.react_to_message(message_id, identity.id, emoji) do
      {:ok, :added, reaction} ->
        json(conn, %{
          action: "added",
          emoji: reaction.emoji,
          previous_emoji: nil,
          message_id: message_id,
          reactions: Messaging.get_message_reactions(message_id)
        })

      {:ok, :removed, removed_emoji} ->
        json(conn, %{
          action: "removed",
          emoji: nil,
          previous_emoji: removed_emoji,
          message_id: message_id,
          reactions: Messaging.get_message_reactions(message_id)
        })

      {:ok, :swapped, reaction, previous_emoji} ->
        json(conn, %{
          action: "swapped",
          emoji: reaction.emoji,
          previous_emoji: previous_emoji,
          message_id: message_id,
          reactions: Messaging.get_message_reactions(message_id)
        })

      {:error, :premium_required} ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          error: "reaction.premium_required",
          message: "This reaction is available on premium tiers."
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "reaction.failed", details: format_errors(changeset)})
    end
  end

  # DELETE /api/v1/conversations/:id/messages/:mid/reactions/:emoji
  def remove_reaction(conn, %{"id" => _conv_id, "mid" => message_id, "emoji" => emoji}) do
    identity = conn.assigns.current_identity

    case Messaging.unreact_to_message(message_id, identity.id, emoji) do
      :ok ->
        json(conn, %{status: "ok"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "reaction.not_found"})
    end
  end

  # GET /api/v1/conversations/:id/messages/:mid/reactions
  def message_reactions(conn, %{"id" => _conv_id, "mid" => message_id}) do
    reactions = Messaging.get_message_reactions(message_id)
    json(conn, reactions)
  end

  defp format_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
