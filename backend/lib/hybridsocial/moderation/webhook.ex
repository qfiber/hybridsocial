defmodule Hybridsocial.Moderation.Webhook do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "moderation_webhooks" do
    field :url, :string
    field :events, {:array, :string}, default: []
    field :secret, :string
    field :enabled, :boolean, default: true

    belongs_to :creator, Hybridsocial.Accounts.Identity, foreign_key: :created_by

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(webhook, attrs) do
    webhook
    |> cast(attrs, [:url, :events, :secret, :enabled, :created_by])
    |> validate_required([:url])
    |> validate_format(:url, ~r/^https?:\/\//, message: "must be a valid URL")
  end
end
