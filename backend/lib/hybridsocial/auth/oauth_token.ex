defmodule Hybridsocial.Auth.OAuthToken do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "oauth_tokens" do
    field :token_hash, :string
    field :refresh_token_hash, :string
    field :scopes, {:array, :string}, default: []
    field :expires_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec
    field :ip_address, :string
    field :user_agent, :string
    field :device_name, :string
    field :last_active_at, :utc_datetime_usec

    belongs_to :identity, Hybridsocial.Accounts.Identity
    belongs_to :application, Hybridsocial.Auth.OAuthApplication

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(token, attrs) do
    token
    |> cast(attrs, [
      :identity_id,
      :application_id,
      :token_hash,
      :refresh_token_hash,
      :scopes,
      :expires_at,
      :ip_address,
      :user_agent,
      :device_name,
      :last_active_at
    ])
    |> validate_required([:identity_id, :token_hash, :scopes, :expires_at])
    |> unique_constraint(:token_hash)
    |> unique_constraint(:refresh_token_hash)
  end

  def revoke_changeset(token) do
    token
    |> change(revoked_at: DateTime.utc_now())
  end
end
