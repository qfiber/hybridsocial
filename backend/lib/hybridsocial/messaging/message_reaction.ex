defmodule Hybridsocial.Messaging.MessageReaction do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "message_reactions" do
    belongs_to :message, Hybridsocial.Messaging.Message
    belongs_to :identity, Hybridsocial.Accounts.Identity
    field :emoji, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(reaction, attrs) do
    reaction
    |> cast(attrs, [:message_id, :identity_id, :emoji])
    |> validate_required([:message_id, :identity_id, :emoji])
    |> validate_length(:emoji, max: 64)
    |> unique_constraint([:message_id, :identity_id, :emoji])
    |> foreign_key_constraint(:message_id)
    |> foreign_key_constraint(:identity_id)
  end
end
