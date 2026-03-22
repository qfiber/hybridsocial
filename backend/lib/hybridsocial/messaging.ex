defmodule Hybridsocial.Messaging do
  @moduledoc """
  The Messaging context. Manages conversations, messages, and DM preferences.
  """
  import Ecto.Query

  alias Hybridsocial.Repo
  alias Hybridsocial.Messaging.{Conversation, Participant, Message, DeliveryStatus, DmPreference}
  alias Hybridsocial.Social

  # ---------------------------------------------------------------------------
  # Conversations
  # ---------------------------------------------------------------------------

  @doc "Find an existing direct conversation between two identities, or create one."
  def find_or_create_direct(sender_id, recipient_id) do
    with :ok <- check_not_self(sender_id, recipient_id),
         :ok <- check_can_dm(sender_id, recipient_id) do
      case find_direct_conversation(sender_id, recipient_id) do
        %Conversation{} = conv ->
          {:ok, conv}

        nil ->
          create_direct_conversation(sender_id, recipient_id)
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

    Ecto.Multi.new()
    |> Ecto.Multi.insert(
      :conversation,
      Conversation.changeset(%Conversation{}, %{type: "direct"})
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
          Conversation.changeset(%Conversation{}, %{type: "group_dm"})
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
          {:ok, Repo.preload(conversation, [:participants])}
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

      message_attrs =
        attrs
        |> Map.put("conversation_id", conversation_id)
        |> Map.put("sender_id", sender_id)

      Ecto.Multi.new()
      |> Ecto.Multi.insert(:message, Message.changeset(%Message{created_at: now}, message_attrs))
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
          {:ok, message}

        {:error, :message, changeset, _changes} ->
          {:error, changeset}

        {:error, _step, reason, _changes} ->
          {:error, reason}
      end
    end
  end

  @doc "Edit a message. Only the sender can edit."
  def edit_message(message_id, sender_id, new_content) do
    case Repo.get(Message, message_id) do
      nil ->
        {:error, :not_found}

      %Message{sender_id: ^sender_id, deleted_at: nil} = message ->
        message
        |> Message.edit_changeset(%{content: new_content, edited_at: DateTime.utc_now()})
        |> Repo.update()

      %Message{deleted_at: deleted_at} when not is_nil(deleted_at) ->
        {:error, :not_found}

      %Message{} ->
        {:error, :forbidden}
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

      {:ok, messages}
    else
      {:error, :not_found}
    end
  end

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
            participant
            |> Ecto.Changeset.change(last_read_message_id: message.id)
            |> Repo.update()
        end
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
end
