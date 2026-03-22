defmodule Hybridsocial.Repo.Migrations.CreateMessaging do
  use Ecto.Migration

  def up do
    # Enum types
    execute("CREATE TYPE conversation_type AS ENUM ('direct', 'group_dm')")
    execute("CREATE TYPE message_content_type AS ENUM ('text', 'image', 'video', 'file')")
    execute("CREATE TYPE message_delivery AS ENUM ('sent', 'delivered', 'read')")

    execute(
      "CREATE TYPE dm_allow_from AS ENUM ('everyone', 'followers', 'mutual_followers', 'nobody')"
    )

    # Conversations
    create table(:conversations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :type, :conversation_type, null: false

      timestamps(type: :utc_datetime_usec)
    end

    # Conversation participants
    create table(:conversation_participants, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :conversation_id, references(:conversations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :identity_id, references(:identities, type: :binary_id, on_delete: :delete_all),
        null: false

      add :joined_at, :utc_datetime_usec, default: fragment("NOW()")
      add :last_read_message_id, :binary_id
      add :notifications_enabled, :boolean, default: true
      add :left_at, :utc_datetime_usec
    end

    create unique_index(:conversation_participants, [:conversation_id, :identity_id])
    create index(:conversation_participants, [:identity_id])

    # Messages
    create table(:messages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :conversation_id, references(:conversations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :sender_id, references(:identities, type: :binary_id, on_delete: :delete_all),
        null: false

      add :content, :text, null: false
      add :content_type, :message_content_type, default: "text"
      add :media_id, references(:media, type: :binary_id, on_delete: :nilify_all)
      add :reply_to_id, references(:messages, type: :binary_id, on_delete: :nilify_all)
      add :edited_at, :utc_datetime_usec
      add :created_at, :utc_datetime_usec, default: fragment("NOW()")
      add :deleted_at, :utc_datetime_usec
    end

    create index(:messages, [:conversation_id, :created_at])
    create index(:messages, [:sender_id])

    # Message delivery status
    create table(:message_delivery_status, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :message_id, references(:messages, type: :binary_id, on_delete: :delete_all),
        null: false

      add :recipient_id, references(:identities, type: :binary_id, on_delete: :delete_all),
        null: false

      add :status, :message_delivery, null: false

      add :updated_at, :utc_datetime_usec, default: fragment("NOW()")
    end

    create unique_index(:message_delivery_status, [:message_id, :recipient_id])

    # DM preferences
    create table(:dm_preferences, primary_key: false) do
      add :identity_id, references(:identities, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :allow_dms_from, :dm_allow_from, default: "everyone"
      add :allow_group_dms, :boolean, default: false
    end
  end

  def down do
    drop table(:dm_preferences)
    drop table(:message_delivery_status)
    drop table(:messages)
    drop table(:conversation_participants)
    drop table(:conversations)

    execute("DROP TYPE dm_allow_from")
    execute("DROP TYPE message_delivery")
    execute("DROP TYPE message_content_type")
    execute("DROP TYPE conversation_type")
  end
end
