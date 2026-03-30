defmodule HybridsocialWeb.Api.V1.ConversationController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Messaging
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

    case Messaging.send_message(conversation_id, identity.id, attrs) do
      {:ok, message} ->
        message = Hybridsocial.Repo.preload(message, [:sender])

        conn
        |> put_status(:created)
        |> json(serialize_message(message))

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "conversation.not_found"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
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
        json(conn, Enum.map(messages, &serialize_message/1))

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "conversation.not_found"})
    end
  end

  # PUT /api/v1/conversations/:id/messages/:mid
  def edit_message(conn, %{"id" => _conversation_id, "mid" => message_id} = params) do
    identity = conn.assigns.current_identity
    new_content = Map.get(params, "content", "")

    case Messaging.edit_message(message_id, identity.id, new_content) do
      {:ok, message} ->
        message = Hybridsocial.Repo.preload(message, [:sender])
        json(conn, serialize_message(message))

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "message.not_found"})

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "message.forbidden"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
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

    %{
      id: conversation.id,
      type: conversation.type,
      accepted: conversation.accepted,
      is_local: conversation.is_local,
      is_encrypted: conversation.is_local == true,
      created_by_id: conversation.created_by_id,
      participants: participants,
      created_at: conversation.inserted_at,
      updated_at: conversation.updated_at
    }
  end

  defp serialize_participant(participant) do
    identity =
      case participant do
        %{identity: %Hybridsocial.Accounts.Identity{} = id} ->
          id

        _ ->
          Hybridsocial.Accounts.get_identity(participant.identity_id)
      end

    %{
      id: participant.id,
      identity_id: participant.identity_id,
      handle: identity && identity.handle,
      display_name: identity && identity.display_name,
      avatar_url: identity && identity.avatar_url,
      joined_at: participant.joined_at,
      notifications_enabled: participant.notifications_enabled,
      left_at: participant.left_at
    }
  end

  defp serialize_message(message) do
    sender =
      case message.sender do
        %Hybridsocial.Accounts.Identity{} = identity ->
          %{
            id: identity.id,
            handle: identity.handle,
            display_name: identity.display_name,
            avatar_url: identity.avatar_url
          }

        _ ->
          nil
      end

    # Get reactions for this message
    reactions = Hybridsocial.Messaging.get_message_reactions(message.id)

    %{
      id: message.id,
      conversation_id: message.conversation_id,
      content: message.content,
      content_type: message.content_type,
      sender: sender,
      media_id: message.media_id,
      reply_to_id: message.reply_to_id,
      reactions: reactions,
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
      {:ok, _} -> json(conn, %{status: "ok"})
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "conversation.not_found"})
    end
  end

  # POST /api/v1/conversations/:id/messages/:mid/reactions
  def add_reaction(conn, %{"id" => _conv_id, "mid" => message_id, "emoji" => emoji}) do
    identity = conn.assigns.current_identity

    case Messaging.react_to_message(message_id, identity.id, emoji) do
      {:ok, reaction} ->
        json(conn, %{id: reaction.id, emoji: reaction.emoji, message_id: reaction.message_id})

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "reaction.failed", details: format_errors(changeset)})
    end
  end

  # DELETE /api/v1/conversations/:id/messages/:mid/reactions/:emoji
  def remove_reaction(conn, %{"id" => _conv_id, "mid" => message_id, "emoji" => emoji}) do
    identity = conn.assigns.current_identity

    case Messaging.unreact_to_message(message_id, identity.id, emoji) do
      :ok -> json(conn, %{status: "ok"})
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
