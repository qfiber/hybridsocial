defmodule Hybridsocial.Federation.Delivery do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @valid_statuses ~w(pending delivered failed retrying)

  schema "federation_deliveries" do
    field :activity_id, :string
    field :actor_id, :binary_id
    field :target_inbox, :string
    field :status, :string, default: "pending"
    field :attempts, :integer, default: 0
    field :last_attempt_at, :utc_datetime_usec
    field :error, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(delivery, attrs) do
    delivery
    |> cast(attrs, [:activity_id, :actor_id, :target_inbox, :status, :attempts, :last_attempt_at, :error])
    |> validate_required([:activity_id, :target_inbox])
    |> validate_inclusion(:status, @valid_statuses)
  end
end
