defmodule Hybridsocial.Messaging.Participant do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "conversation_participants" do
    belongs_to :conversation, Hybridsocial.Messaging.Conversation
    belongs_to :identity, Hybridsocial.Accounts.Identity

    field :joined_at, :utc_datetime_usec
    field :last_read_message_id, :binary_id
    field :notifications_enabled, :boolean, default: true
    field :left_at, :utc_datetime_usec
  end

  def changeset(participant, attrs) do
    participant
    |> cast(attrs, [:conversation_id, :identity_id, :joined_at, :last_read_message_id, :notifications_enabled, :left_at])
    |> validate_required([:conversation_id, :identity_id])
    |> unique_constraint([:conversation_id, :identity_id])
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:identity_id)
  end
end
