defmodule Hybridsocial.Messaging.Conversation do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_types ~w(direct group_dm)

  schema "conversations" do
    field :type, :string
    field :accepted, :boolean, default: false
    field :is_local, :boolean, default: true

    belongs_to :created_by, Hybridsocial.Accounts.Identity

    has_many :participants, Hybridsocial.Messaging.Participant
    has_many :messages, Hybridsocial.Messaging.Message

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:type, :accepted, :is_local, :created_by_id])
    |> validate_required([:type])
    |> validate_inclusion(:type, @valid_types)
    |> foreign_key_constraint(:created_by_id)
  end
end
