defmodule Hybridsocial.Auth.WebauthnCredential do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "webauthn_credentials" do
    belongs_to :identity, Hybridsocial.Accounts.Identity
    field :credential_id, :string
    field :public_key, :string
    field :sign_count, :integer, default: 0
    field :name, :string, default: "Security Key"
    field :last_used_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(cred, attrs) do
    cred
    |> cast(attrs, [:identity_id, :credential_id, :public_key, :sign_count, :name])
    |> validate_required([:identity_id, :credential_id, :public_key])
    |> validate_length(:name, max: 100)
    |> unique_constraint(:credential_id)
    |> foreign_key_constraint(:identity_id)
  end
end
