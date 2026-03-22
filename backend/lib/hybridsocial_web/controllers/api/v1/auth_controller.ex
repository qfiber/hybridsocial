defmodule HybridsocialWeb.Api.V1.AuthController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Accounts
  alias Hybridsocial.Auth
  alias Hybridsocial.Moderation

  def register(conn, params) do
    case Accounts.register_user(params) do
      {:ok, identity} ->
        Moderation.log(
          identity.id,
          "auth.register",
          "identity",
          identity.id,
          %{handle: identity.handle},
          get_client_ip(conn)
        )

        conn
        |> put_status(:created)
        |> json(%{
          id: identity.id,
          handle: identity.handle,
          display_name: identity.display_name,
          message: "account.confirmation_required"
        })

      {:error, :pow_required} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "auth.pow_required"})

      {:error, :captcha_failed} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "auth.captcha_failed"})

      {:error, :email_domain_banned} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "auth.email_domain_banned"})

      {:error, :handle_reserved} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "auth.handle_reserved"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  def login(conn, %{"email" => email, "password" => password}) do
    case Auth.login(email, password) do
      {:ok, tokens} ->
        Moderation.log(
          tokens.identity_id,
          "auth.login",
          "identity",
          tokens.identity_id,
          %{method: "password"},
          get_client_ip(conn)
        )

        conn
        |> put_status(:ok)
        |> json(tokens)

      {:error, :otp_required, identity_id} ->
        conn
        |> put_status(:ok)
        |> json(%{otp_required: true, identity_id: identity_id})

      {:error, :invalid_credentials} ->
        Moderation.log(nil, "auth.login_failed", nil, nil, %{email: email}, get_client_ip(conn))

        conn
        |> put_status(:unauthorized)
        |> json(%{error: "auth.invalid_credentials"})

      {:error, :account_suspended} ->
        Moderation.log(
          nil,
          "auth.login_failed",
          nil,
          nil,
          %{email: email, reason: "suspended"},
          get_client_ip(conn)
        )

        conn
        |> put_status(:unauthorized)
        |> json(%{error: "auth.invalid_credentials"})

      {:error, :account_deleted} ->
        Moderation.log(
          nil,
          "auth.login_failed",
          nil,
          nil,
          %{email: email, reason: "deleted"},
          get_client_ip(conn)
        )

        conn
        |> put_status(:unauthorized)
        |> json(%{error: "auth.invalid_credentials"})
    end
  end

  def refresh(conn, %{"refresh_token" => refresh_token}) do
    case Auth.refresh(refresh_token) do
      {:ok, tokens} ->
        conn
        |> put_status(:ok)
        |> json(tokens)

      {:error, :invalid_refresh_token} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "auth.invalid_refresh_token"})
    end
  end

  def logout(conn, _params) do
    token = conn.assigns[:current_token]
    identity = conn.assigns[:current_identity]
    Auth.logout(token)

    if identity do
      Moderation.log(
        identity.id,
        "auth.logout",
        "identity",
        identity.id,
        %{},
        get_client_ip(conn)
      )
    end

    conn
    |> put_status(:ok)
    |> json(%{message: "auth.logged_out"})
  end

  def confirm(conn, %{"token" => token}) do
    case Accounts.confirm_user(token) do
      {:ok, _user} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "account.confirmed"})

      {:error, :invalid_token} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "auth.invalid_confirmation_token"})
    end
  end

  def me(conn, _params) do
    identity = conn.assigns.current_identity
    identity = Hybridsocial.Repo.preload(identity, :user)

    roles = Hybridsocial.Auth.RBAC.get_roles(identity.id)
    permissions = Hybridsocial.Auth.RBAC.get_permissions(identity.id)

    conn
    |> put_status(:ok)
    |> json(%{
      id: identity.id,
      type: identity.type,
      handle: identity.handle,
      display_name: identity.display_name,
      bio: identity.bio,
      avatar_url: identity.avatar_url,
      header_url: identity.header_url,
      is_locked: identity.is_locked,
      is_bot: identity.is_bot,
      is_admin: identity.is_admin,
      roles: roles,
      permissions: permissions,
      created_at: identity.inserted_at,
      email: identity.user && identity.user.email,
      confirmed: identity.user && identity.user.confirmed_at != nil,
      two_factor_enabled: identity.user && identity.user.otp_enabled,
      locale: identity.user && identity.user.locale
    })
  end

  # --- 2FA endpoints ---

  def setup_2fa(conn, _params) do
    identity_id = conn.assigns.current_identity.id

    case Accounts.setup_2fa(identity_id) do
      {:ok, %{secret: secret, uri: uri}} ->
        conn
        |> put_status(:ok)
        |> json(%{secret: secret, uri: uri})

      {:error, _reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "2fa.setup_failed"})
    end
  end

  def verify_2fa(conn, %{"code" => code}) do
    identity_id = conn.assigns.current_identity.id

    case Accounts.enable_2fa(identity_id, code) do
      {:ok, _user} ->
        Moderation.log(
          identity_id,
          "auth.2fa_enabled",
          "identity",
          identity_id,
          %{},
          get_client_ip(conn)
        )

        conn
        |> put_status(:ok)
        |> json(%{message: "2fa.enabled"})

      {:error, :invalid_code} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "2fa.invalid_code"})

      {:error, _reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "2fa.verify_failed"})
    end
  end

  def disable_2fa(conn, %{"code" => code}) do
    identity_id = conn.assigns.current_identity.id

    case Accounts.disable_2fa(identity_id, code) do
      {:ok, _user} ->
        Moderation.log(
          identity_id,
          "auth.2fa_disabled",
          "identity",
          identity_id,
          %{},
          get_client_ip(conn)
        )

        conn
        |> put_status(:ok)
        |> json(%{message: "2fa.disabled"})

      {:error, :invalid_code} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "2fa.invalid_code"})

      {:error, _reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "2fa.disable_failed"})
    end
  end

  def login_with_otp(conn, %{"identity_id" => identity_id, "code" => code}) do
    case Auth.login_with_otp(identity_id, code) do
      {:ok, tokens} ->
        Moderation.log(
          identity_id,
          "auth.login_2fa",
          "identity",
          identity_id,
          %{},
          get_client_ip(conn)
        )

        conn
        |> put_status(:ok)
        |> json(tokens)

      {:error, :invalid_code} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "2fa.invalid_code"})

      {:error, _reason} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "auth.invalid_credentials"})
    end
  end

  # --- Password Reset ---

  def password_reset(conn, %{"email" => email}) do
    Moderation.log(
      nil,
      "auth.password_reset_requested",
      nil,
      nil,
      %{email: email},
      get_client_ip(conn)
    )

    Accounts.request_password_reset(email)
    json(conn, %{message: "auth.reset_email_sent"})
  end

  def password_change(conn, %{
        "token" => token,
        "password" => password,
        "password_confirmation" => confirmation
      }) do
    case Accounts.reset_password(token, password, confirmation) do
      {:ok, user} ->
        Moderation.log(
          user.identity_id,
          "auth.password_changed",
          "identity",
          user.identity_id,
          %{},
          get_client_ip(conn)
        )

        json(conn, %{message: "auth.password_changed"})

      {:error, :invalid_token} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "auth.invalid_reset_token"})

      {:error, :token_expired} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "auth.reset_token_expired"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  # --- PoW Challenge ---

  def pow_challenge(conn, _params) do
    challenge = Hybridsocial.Auth.PoW.generate_challenge()
    json(conn, challenge)
  end

  defp get_client_ip(conn) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [ip | _] -> ip |> String.split(",") |> hd() |> String.trim()
      [] -> conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
