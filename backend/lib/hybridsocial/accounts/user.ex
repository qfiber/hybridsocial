defmodule Hybridsocial.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:identity_id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "users" do
    field :email, :string
    field :password_hash, :string
    field :locale, :string, default: "en"
    field :timezone, :string
    field :last_login_at, :utc_datetime_usec
    field :confirmed_at, :utc_datetime_usec
    field :confirmation_token, :string
    field :confirmation_sent_at, :utc_datetime_usec
    field :reset_token, :string
    field :reset_token_at, :utc_datetime_usec
    field :otp_secret, :string
    field :otp_enabled, :boolean, default: false
    field :recovery_codes_hash, :string

    # Virtual fields
    field :password, :string, virtual: true
    field :password_confirmation, :string, virtual: true

    belongs_to :identity, Hybridsocial.Accounts.Identity,
      foreign_key: :identity_id,
      references: :id,
      define_field: false

    timestamps(type: :utc_datetime_usec)
  end

  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :password, :password_confirmation, :locale, :timezone])
    |> validate_required([:email, :password, :password_confirmation])
    |> validate_email()
    |> validate_password()
    |> put_password_hash()
    |> put_confirmation_token()
  end

  def password_changeset(user, attrs) do
    user
    |> cast(attrs, [:password, :password_confirmation])
    |> validate_required([:password, :password_confirmation])
    |> validate_password()
    |> put_password_hash()
  end

  def confirm_changeset(user) do
    user
    |> change(confirmed_at: DateTime.utc_now(), confirmation_token: nil)
  end

  def login_changeset(user) do
    user
    |> change(last_login_at: DateTime.utc_now())
  end

  @doc "Stores the OTP secret on the user (does NOT enable 2FA yet)."
  def otp_setup_changeset(user, secret) do
    user
    |> change(otp_secret: Base.encode32(secret, padding: false))
  end

  @doc "Enables 2FA after the user has verified a code."
  def otp_enable_changeset(user) do
    user
    |> change(otp_enabled: true)
  end

  @doc "Disables 2FA and clears the secret and recovery codes."
  def otp_disable_changeset(user) do
    user
    |> change(otp_secret: nil, otp_enabled: false, recovery_codes_hash: nil)
  end

  defp validate_email(changeset) do
    changeset
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/, message: "must be a valid email")
    |> validate_length(:email, max: 254)
    |> unique_constraint(:email)
    |> update_change(:email, &String.downcase/1)
  end

  defp validate_password(changeset) do
    changeset
    |> validate_length(:password, min: 8, max: 128)
    |> validate_confirmation(:password, message: "passwords do not match")
  end

  defp put_password_hash(changeset) do
    case get_change(changeset, :password) do
      nil -> changeset
      password -> put_change(changeset, :password_hash, Bcrypt.hash_pwd_salt(password))
    end
  end

  defp put_confirmation_token(changeset) do
    if changeset.valid? do
      token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

      changeset
      |> put_change(:confirmation_token, token)
      |> put_change(:confirmation_sent_at, DateTime.utc_now())
    else
      changeset
    end
  end
end
