defmodule Hybridsocial.Push.Subscription do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "push_subscriptions" do
    field :endpoint, :string
    field :key_p256dh, :string
    field :key_auth, :string
    field :user_agent, :string
    belongs_to :identity, Hybridsocial.Accounts.Identity
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(sub, attrs) do
    sub
    |> cast(attrs, [:identity_id, :endpoint, :key_p256dh, :key_auth, :user_agent])
    |> validate_required([:identity_id, :endpoint, :key_p256dh, :key_auth])
    |> unique_constraint([:identity_id, :endpoint])
  end
end
