defmodule Hybridsocial.Messaging.Message do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_content_types ~w(text image video file)

  schema "messages" do
    belongs_to :conversation, Hybridsocial.Messaging.Conversation
    belongs_to :sender, Hybridsocial.Accounts.Identity
    belongs_to :media, Hybridsocial.Media.MediaFile
    belongs_to :reply_to, Hybridsocial.Messaging.Message

    field :content, :string
    field :content_type, :string, default: "text"
    field :edited_at, :utc_datetime_usec
    field :created_at, :utc_datetime_usec
    field :deleted_at, :utc_datetime_usec
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [
      :conversation_id,
      :sender_id,
      :content,
      :content_type,
      :media_id,
      :reply_to_id
    ])
    |> validate_required([:conversation_id, :sender_id, :content])
    |> validate_inclusion(:content_type, @valid_content_types)
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:sender_id)
    |> foreign_key_constraint(:media_id)
    |> foreign_key_constraint(:reply_to_id)
  end

  def edit_changeset(message, attrs) do
    message
    |> cast(attrs, [:content, :edited_at])
    |> validate_required([:content])
  end

  def delete_changeset(message) do
    message
    |> change(deleted_at: DateTime.utc_now())
  end
end
