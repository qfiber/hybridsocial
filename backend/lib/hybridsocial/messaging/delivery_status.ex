defmodule Hybridsocial.Messaging.DeliveryStatus do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_statuses ~w(sent delivered read)

  schema "message_delivery_status" do
    belongs_to :message, Hybridsocial.Messaging.Message
    belongs_to :recipient, Hybridsocial.Accounts.Identity

    field :status, :string

    field :updated_at, :utc_datetime_usec
  end

  def changeset(delivery_status, attrs) do
    delivery_status
    |> cast(attrs, [:message_id, :recipient_id, :status])
    |> validate_required([:message_id, :recipient_id, :status])
    |> validate_inclusion(:status, @valid_statuses)
    |> unique_constraint([:message_id, :recipient_id])
    |> foreign_key_constraint(:message_id)
    |> foreign_key_constraint(:recipient_id)
  end
end
