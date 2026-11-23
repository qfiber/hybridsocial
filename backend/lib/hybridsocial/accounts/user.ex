defmodule Hybridsocial.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:identity_id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "users" do
    # Email is encrypted at rest; `email_hash` is a deterministic blind
    # index (keyed HMAC) that carries uniqueness + login lookups, since the
    # randomized ciphertext can't be searched or unique-constrained.
    field :email, Hybridsocial.Crypto.EncryptedBinary, context: "user.email"
    field :email_hash, :string
    # Requested change, applied only once the new address confirms it.
    field :pending_email, Hybridsocial.Crypto.EncryptedBinary, context: "user.pending_email"
    field :pending_email_token, :string
    field :pending_email_sent_at, :utc_datetime_usec
    field :password_hash, :string
    field :locale, :string, default: "en"
    field :timezone, :string
    field :default_visibility, :string, default: "public"
    field :preferences, :map, default: %{}
    field :last_login_at, :utc_datetime_usec
    field :confirmed_at, :utc_datetime_usec
    field :confirmation_token, :string
    field :confirmation_sent_at, :utc_datetime_usec
    field :reset_token, :string
    field :reset_token_at, :utc_datetime_usec
    field :otp_secret, Hybridsocial.Crypto.EncryptedBinary, context: "user.otp_secret"
    field :otp_enabled, :boolean, default: false
    field :recovery_codes_hash, :string
    field :approved_at, :utc_datetime_usec
    field :approval_required, :boolean, default: false
    field :notification_digest_at, :utc_datetime_usec

    # Virtual fields
    field :password, :string, virtual: true
    field :password_confirmation, :string, virtual: true
    field :confirmation_token_plaintext, :string, virtual: true
    field :reset_token_plaintext, :string, virtual: true

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

  @doc """
  Changeset for changing an existing user's email. Runs the full `validate_email`
  pipeline so the new address is encrypted AND `email_hash` (the blind index that
  login and uniqueness rely on) is recomputed. A bare `change(email: ...)` leaves
  `email_hash` pointing at the old address, which silently breaks login.
  """
  def email_changeset(user, new_email) do
    user
    |> cast(%{email: new_email}, [:email])
    |> validate_required([:email])
    |> validate_email()
  end

  @doc "Validates and normalizes a requested new address (not yet applied)."
  def pending_email_changeset(user, new_email) do
    user
    |> cast(%{pending_email: new_email}, [:pending_email])
    |> validate_required([:pending_email])
    |> validate_format(:pending_email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/,
      message: "must be a valid email"
    )
    |> validate_length(:pending_email, max: 254)
    |> update_change(:pending_email, &String.downcase/1)
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
    |> update_change(:email, &String.downcase/1)
    |> put_email_hash()
    # Surface the uniqueness error on :email (the field the API/UI knows)
    # rather than :email_hash (the internal blind index it's enforced on).
    |> unique_constraint(:email, name: :users_email_hash_index)
  end

  # Blind index of the (normalized) email — the searchable/unique key.
  defp put_email_hash(changeset) do
    case fetch_field(changeset, :email) do
      {_, email} when is_binary(email) ->
        put_change(changeset, :email_hash, Hybridsocial.Crypto.blind_index(email, "user.email"))

      _ ->
        changeset
    end
  end

  defp validate_password(changeset) do
    changeset
    |> validate_length(:password, min: 16, max: 128)
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
      hashed = hash_token(token)

      changeset
      |> put_change(:confirmation_token, hashed)
      |> put_change(:confirmation_token_plaintext, token)
      |> put_change(:confirmation_sent_at, DateTime.utc_now())
    else
      changeset
    end
  end

  @doc "Hashes a token using SHA-256 for secure storage."
  def hash_token(token) do
    :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
  end
end
