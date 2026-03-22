defmodule Hybridsocial.Accounts do
  @moduledoc """
  The Accounts context. Manages identities, users, and organizations.
  """
  import Ecto.Query
  alias Hybridsocial.Repo
  alias Hybridsocial.Accounts.{Identity, User}

  # --- Identity queries ---

  def get_identity(id) do
    Identity
    |> where([i], is_nil(i.deleted_at))
    |> Repo.get(id)
  end

  def get_identity!(id) do
    Identity
    |> where([i], is_nil(i.deleted_at))
    |> Repo.get!(id)
  end

  def get_identity_by_handle(handle) do
    Identity
    |> where([i], i.handle == ^handle and is_nil(i.deleted_at))
    |> Repo.one()
  end

  def get_identity_with_user(id) do
    Identity
    |> where([i], is_nil(i.deleted_at))
    |> Repo.get(id)
    |> Repo.preload(:user)
  end

  # --- User registration ---

  def register_user(attrs) do
    with :ok <- check_pow(attrs),
         :ok <- check_turnstile(attrs),
         :ok <- check_email_domain(attrs),
         :ok <- check_handle_available(attrs) do
      do_register_user(attrs)
    end
  end

  defp do_register_user(attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:identity, fn _ ->
      %Identity{}
      |> Identity.create_changeset(Map.merge(attrs, %{"type" => "user"}))
    end)
    |> Ecto.Multi.insert(:user, fn %{identity: identity} ->
      %User{identity_id: identity.id}
      |> User.registration_changeset(attrs)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{identity: identity, user: user}} ->
        # Send confirmation email with plaintext token for the link
        email_user = %{user | confirmation_token: user.confirmation_token_plaintext}

        try do
          email_user
          |> Hybridsocial.Emails.confirmation_email()
          |> Hybridsocial.Mailer.deliver()
        rescue
          _ -> :ok
        end

        {:ok, %{identity | user: user}}

      {:error, :identity, changeset, _} ->
        {:error, changeset}

      {:error, :user, changeset, _} ->
        {:error, changeset}
    end
  end

  defp check_pow(attrs) do
    if Hybridsocial.Auth.PoW.enabled?() do
      prefix = attrs["pow_prefix"]
      nonce = attrs["pow_nonce"]

      if prefix && nonce && Hybridsocial.Auth.PoW.verify(prefix, nonce) do
        :ok
      else
        {:error, :pow_required}
      end
    else
      :ok
    end
  end

  defp check_turnstile(attrs) do
    if Hybridsocial.Auth.Turnstile.enabled?() do
      case Hybridsocial.Auth.Turnstile.verify(attrs["cf_turnstile_token"]) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end

  defp check_email_domain(attrs) do
    case attrs["email"] do
      nil ->
        :ok

      email ->
        domain = email |> String.split("@") |> List.last()

        if function_exported?(Hybridsocial.Moderation, :domain_banned?, 2) do
          try do
            if Hybridsocial.Moderation.domain_banned?(domain, "email") do
              {:error, :email_domain_banned}
            else
              :ok
            end
          rescue
            _ -> :ok
          end
        else
          :ok
        end
    end
  end

  defp check_handle_available(attrs) do
    case attrs["handle"] do
      nil ->
        :ok

      handle ->
        if handle_reserved?(handle) do
          {:error, :handle_reserved}
        else
          :ok
        end
    end
  end

  # --- Authentication ---

  def get_user_by_email(email) do
    email = String.downcase(email)

    User
    |> where([u], u.email == ^email)
    |> Repo.one()
    |> case do
      nil -> nil
      user -> Repo.preload(user, :identity)
    end
  end

  def authenticate_user(email, password) do
    case get_user_by_email(email) do
      nil ->
        # Prevent timing attacks
        Bcrypt.no_user_verify()
        {:error, :invalid_credentials}

      user ->
        if user.identity.is_suspended do
          {:error, :account_suspended}
        else
          if user.identity.deleted_at do
            {:error, :account_deleted}
          else
            if Bcrypt.verify_pass(password, user.password_hash) do
              {:ok, user}
            else
              {:error, :invalid_credentials}
            end
          end
        end
    end
  end

  # --- Email confirmation ---

  def confirm_user(token) do
    hashed = User.hash_token(token)

    User
    |> where([u], u.confirmation_token == ^hashed)
    |> Repo.one()
    |> case do
      nil ->
        {:error, :invalid_token}

      user ->
        user
        |> User.confirm_changeset()
        |> Repo.update()
    end
  end

  # --- Profile updates ---

  def update_identity(identity, attrs) do
    identity
    |> Identity.update_changeset(attrs)
    |> Repo.update()
  end

  def change_handle(identity, new_handle) do
    old_handle = identity.handle

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:handle_history, fn _ ->
      %Hybridsocial.Accounts.HandleHistory{
        identity_id: identity.id,
        old_handle: old_handle,
        changed_at: DateTime.utc_now(),
        reserved_until: DateTime.add(DateTime.utc_now(), 365 * 24 * 3600, :second)
      }
    end)
    |> Ecto.Multi.update(:identity, fn _ ->
      identity
      |> Ecto.Changeset.change(handle: new_handle)
      |> Ecto.Changeset.unique_constraint(:handle)
    end)
    |> Repo.transaction()
  end

  def handle_reserved?(handle) do
    Hybridsocial.Accounts.HandleHistory
    |> where([h], h.old_handle == ^handle and h.reserved_until > ^DateTime.utc_now())
    |> Repo.exists?()
  end

  # --- Account deletion ---

  def soft_delete_identity(identity) do
    identity
    |> Identity.soft_delete_changeset()
    |> Repo.update()
  end

  # --- Listing ---

  def list_identities(opts \\ []) do
    Identity
    |> where([i], is_nil(i.deleted_at))
    |> filter_by_type(opts[:type])
    |> order_by([i], desc: i.inserted_at)
    |> Repo.all()
  end

  defp filter_by_type(query, nil), do: query
  defp filter_by_type(query, type), do: where(query, [i], i.type == ^type)

  # --- Password Reset ---

  def request_password_reset(email) do
    case get_user_by_email(email) do
      nil ->
        # Don't leak whether email exists
        {:ok, :sent}

      user ->
        token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
        hashed = User.hash_token(token)

        user
        |> Ecto.Changeset.change(
          reset_token: hashed,
          reset_token_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
        )
        |> Repo.update()

        # Pass the plaintext token for the email link
        email_user = %{user | reset_token: token}

        try do
          email_user
          |> Hybridsocial.Emails.password_reset_email()
          |> Hybridsocial.Mailer.deliver()
        rescue
          _ -> :ok
        end

        {:ok, :sent}
    end
  end

  def reset_password(token, password, password_confirmation) do
    hashed = User.hash_token(token)

    case Repo.one(from u in User, where: u.reset_token == ^hashed) do
      nil ->
        {:error, :invalid_token}

      user ->
        # Check expiry (1 hour)
        if DateTime.diff(DateTime.utc_now(), user.reset_token_at) > 3600 do
          {:error, :token_expired}
        else
          result =
            user
            |> User.password_changeset(%{
              "password" => password,
              "password_confirmation" => password_confirmation
            })
            |> Ecto.Changeset.put_change(:reset_token, nil)
            |> Ecto.Changeset.put_change(:reset_token_at, nil)
            |> Repo.update()

          # Revoke all existing tokens for this user on password change
          case result do
            {:ok, _} ->
              revoke_all_tokens(user.identity_id)
              result

            error ->
              error
          end
        end
    end
  end

  defp revoke_all_tokens(identity_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    from(t in Hybridsocial.Auth.OAuthToken,
      where: t.identity_id == ^identity_id and is_nil(t.revoked_at)
    )
    |> Repo.update_all(set: [revoked_at: now])
  end

  # --- Two-Factor Authentication ---

  alias Hybridsocial.Auth.TOTP

  @doc "Generates a TOTP secret, stores it on the user, returns secret + URI."
  def setup_2fa(identity_id) do
    case get_user(identity_id) do
      nil ->
        {:error, :not_found}

      user ->
        secret = TOTP.generate_secret()

        case user |> User.otp_setup_changeset(secret) |> Repo.update() do
          {:ok, _user} ->
            uri = TOTP.generate_uri(secret, user.email)
            encoded_secret = Base.encode32(secret, padding: false)
            {:ok, %{secret: encoded_secret, uri: uri}}

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  @doc "Verifies the TOTP code and enables 2FA."
  def enable_2fa(identity_id, code) do
    case get_user(identity_id) do
      nil ->
        {:error, :not_found}

      user ->
        with {:ok, secret} <- decode_otp_secret(user),
             true <- TOTP.valid_code?(secret, code) do
          user |> User.otp_enable_changeset() |> Repo.update()
        else
          _ -> {:error, :invalid_code}
        end
    end
  end

  @doc "Verifies the TOTP code and disables 2FA."
  def disable_2fa(identity_id, code) do
    case get_user(identity_id) do
      nil ->
        {:error, :not_found}

      user ->
        with {:ok, secret} <- decode_otp_secret(user),
             true <- TOTP.valid_code?(secret, code) do
          user |> User.otp_disable_changeset() |> Repo.update()
        else
          _ -> {:error, :invalid_code}
        end
    end
  end

  @doc "Verifies a TOTP code for login."
  def verify_2fa(identity_id, code) do
    case get_user(identity_id) do
      nil ->
        {:error, :not_found}

      user ->
        with {:ok, secret} <- decode_otp_secret(user),
             true <- TOTP.valid_code?(secret, code) do
          {:ok, user}
        else
          _ -> {:error, :invalid_code}
        end
    end
  end

  defp get_user(identity_id) do
    User
    |> where([u], u.identity_id == ^identity_id)
    |> Repo.one()
  end

  defp decode_otp_secret(%User{otp_secret: nil}), do: {:error, :no_secret}

  defp decode_otp_secret(%User{otp_secret: encoded}) do
    case Base.decode32(encoded, padding: false) do
      {:ok, secret} -> {:ok, secret}
      :error -> {:error, :invalid_secret}
    end
  end
end
