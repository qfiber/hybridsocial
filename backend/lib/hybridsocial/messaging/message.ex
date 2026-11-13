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

    # Plaintext is only populated when encryption_version = 0
    # (legacy / federated import). New local messages always set
    # encryption_version = 1, leave content nil, and store ciphertext + nonce.
    field :content, :string
    field :ciphertext, :binary
    field :nonce, :binary
    field :encryption_version, :integer, default: 0

    field :content_type, :string, default: "text"
    field :edited_at, :utc_datetime_usec
    field :created_at, :utc_datetime_usec
    field :deleted_at, :utc_datetime_usec

    # ActivityPub URL for this message. Local messages: `{base}/dm/{id}`;
    # messages ingested from remote peers: the peer's `object.id`. Drives
    # outbound `inReplyTo` chaining (so Mastodon threads our DMs
    # properly in its private-mentions view) and inbound idempotency.
    field :ap_id, :string
  end

  @doc """
  Changeset for an already-encrypted message. Callers (`Messaging` context)
  encrypt plaintext into ciphertext/nonce via `Messaging.Crypto.encrypt/2`
  before handing the map to this changeset — plaintext never touches the
  DB on the write path.
  """
  def encrypted_changeset(message, attrs) do
    message
    |> cast(attrs, [
      :id,
      :conversation_id,
      :sender_id,
      :ciphertext,
      :nonce,
      :encryption_version,
      :content_type,
      :media_id,
      :reply_to_id,
      :ap_id
    ])
    |> validate_required([:conversation_id, :sender_id, :ciphertext, :nonce, :encryption_version])
    |> validate_inclusion(:content_type, @valid_content_types)
    # A remote ChatMessage id is unbounded; cap it so an absurd one is a
    # changeset error, not a database error (#267).
    |> validate_length(:ap_id, max: 2048, count: :bytes)
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:sender_id)
    |> foreign_key_constraint(:media_id)
    |> foreign_key_constraint(:reply_to_id)
    |> unique_constraint(:ap_id, name: :messages_ap_id_index)
  end

  @doc "Edit changeset for an encrypted message. Re-encrypts before calling."
  def edit_encrypted_changeset(message, attrs) do
    message
    |> cast(attrs, [:ciphertext, :nonce, :encryption_version, :edited_at])
    |> validate_required([:ciphertext, :nonce, :encryption_version])
  end

  def delete_changeset(message) do
    message
    |> change(deleted_at: DateTime.utc_now())
  end
end
