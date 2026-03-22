defmodule Hybridsocial.Federation.Relay do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @valid_statuses ~w(pending accepted rejected)

  schema "relays" do
    field :inbox_url, :string
    field :status, :string, default: "pending"

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(relay, attrs) do
    relay
    |> cast(attrs, [:inbox_url, :status])
    |> validate_required([:inbox_url])
    |> validate_inclusion(:status, @valid_statuses)
    |> unique_constraint(:inbox_url)
  end
end
