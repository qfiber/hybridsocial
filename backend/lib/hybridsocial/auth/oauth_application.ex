defmodule Hybridsocial.Auth.OAuthApplication do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "oauth_applications" do
    field :name, :string
    field :client_id, :string
    field :client_secret_hash, :string
    field :redirect_uris, {:array, :string}, default: []
    field :scopes, {:array, :string}, default: []
    field :website, :string

    belongs_to :creator, Hybridsocial.Accounts.Identity, foreign_key: :created_by

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(app, attrs) do
    app
    |> cast(attrs, [:name, :redirect_uris, :scopes, :website])
    |> validate_required([:name])
    |> generate_credentials()
  end

  defp generate_credentials(changeset) do
    if changeset.valid? and is_nil(get_field(changeset, :client_id)) do
      client_id = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
      client_secret = :crypto.strong_rand_bytes(64) |> Base.url_encode64(padding: false)
      secret_hash = :crypto.hash(:sha256, client_secret) |> Base.encode16(case: :lower)

      changeset
      |> put_change(:client_id, client_id)
      |> put_change(:client_secret_hash, secret_hash)
    else
      changeset
    end
  end
end
