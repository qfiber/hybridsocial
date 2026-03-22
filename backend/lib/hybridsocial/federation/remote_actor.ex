defmodule Hybridsocial.Federation.RemoteActor do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "remote_actors" do
    field :ap_id, :string
    field :handle, :string
    field :domain, :string
    field :display_name, :string
    field :avatar_url, :string
    field :public_key, :string
    field :inbox_url, :string
    field :outbox_url, :string
    field :followers_url, :string
    field :shared_inbox_url, :string
    field :last_fetched_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(remote_actor, attrs) do
    remote_actor
    |> cast(attrs, [
      :ap_id,
      :handle,
      :domain,
      :display_name,
      :avatar_url,
      :public_key,
      :inbox_url,
      :outbox_url,
      :followers_url,
      :shared_inbox_url,
      :last_fetched_at
    ])
    |> validate_required([:ap_id])
    |> unique_constraint(:ap_id)
  end
end
