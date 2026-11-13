defmodule Hybridsocial.AccountsFixtures do
  @moduledoc """
  Central factory for test accounts, plus the conn helpers that
  authenticate them. Imported automatically into every `DataCase` and
  `ConnCase`, so test modules must NOT define their own
  `create_user`/`auth_conn`/`create_admin` helpers — extend this module
  instead. That is the whole point: an auth change (a new gate, a
  different token shape) is a one-line fix here, not a sweep across ~40
  test files.

  `create_user/2` returns a CONFIRMED user because the
  `RequireConfirmedEmail` plug (email confirmation defaults to on) 403s
  unconfirmed users on every authenticated endpoint, and a real actor
  performing these actions has confirmed their email. Tests that
  specifically exercise the confirmation gate use
  `create_unconfirmed_user/2`.
  """
  alias Hybridsocial.{Accounts, Repo}
  alias Hybridsocial.Accounts.User
  alias Hybridsocial.Auth.{OAuthToken, RBAC, Token}

  @password "password1234567890"

  @doc "The shared test password (satisfies the registration policy)."
  def valid_password, do: @password

  @doc """
  Register a confirmed user and return its identity. `email` defaults to
  `<handle>@test.com`.
  """
  def create_user(handle, email \\ nil) do
    handle
    |> register(email)
    |> confirm_email()
  end

  @doc """
  A confirmed user past the new-account gates (trust level 1), for tests of
  features rather than of `Accounts.Trust`: a fresh account can't post links
  or DM people who don't follow it.
  """
  def create_trusted_user(handle, email \\ nil) do
    handle |> create_user(email) |> make_trusted()
  end

  @doc "Raise an identity to `level` (default 1), as the trust computation would."
  def make_trusted(identity, level \\ 1) do
    identity
    |> Ecto.Changeset.change(trust_level: level)
    |> Repo.update!()
  end

  @doc """
  Register an UNCONFIRMED user (confirmed_at: nil) — for tests that
  exercise the email-confirmation gate itself. Returns the identity.
  """
  def create_unconfirmed_user(handle, email \\ nil) do
    register(handle, email)
  end

  @doc "Confirmed user + owner role + OTP enabled — a full admin actor."
  def create_admin(handle, email \\ nil) do
    handle |> create_user(email) |> make_admin()
  end

  @doc "Confirmed user + moderator role + OTP enabled."
  def create_moderator(handle, email \\ nil) do
    handle |> create_user(email) |> make_moderator()
  end

  @doc """
  Grant an existing identity the owner role + OTP (step-up ready).
  Returns the identity.
  """
  def make_admin(identity) do
    {:ok, _} = RBAC.assign_role(identity.id, "owner", identity.id)
    enable_otp(identity)
  end

  @doc "Grant an existing identity the moderator role + OTP. Returns the identity."
  def make_moderator(identity) do
    {:ok, _} = RBAC.assign_role(identity.id, "moderator", identity.id)
    enable_otp(identity)
  end

  @doc "Mark the identity's user record email-confirmed. Returns the identity."
  def confirm_email(identity) do
    Accounts.get_user_by_identity(identity.id)
    |> User.confirm_changeset()
    |> Repo.update!()

    identity
  end

  @doc "Enable TOTP on the identity's user record. Returns the identity."
  def enable_otp(identity) do
    Accounts.get_user_by_identity(identity.id)
    |> Ecto.Changeset.change(otp_enabled: true)
    |> Repo.update!()

    identity
  end

  @doc "Attach a bearer access token for `identity` to the conn."
  def auth_conn(conn, identity) do
    {:ok, token, _} = Token.generate_access_token(identity.id)
    now = DateTime.utc_now()

    # Real login persists an oauth_tokens row per access token, and the auth
    # plug now enforces revocation by requiring a live, non-revoked row — so
    # a bare JWT with no row 401s. Mirror login and create the row.
    %OAuthToken{}
    |> OAuthToken.changeset(%{
      identity_id: identity.id,
      token_hash: Token.hash_token(token),
      scopes: ["read", "write"],
      expires_at: DateTime.add(now, Token.access_token_ttl(), :second)
    })
    |> Repo.insert!()

    Plug.Conn.put_req_header(conn, "authorization", "Bearer #{token}")
  end

  @doc """
  Like `auth_conn/2`, but also opens a sudo (step-up) window on the
  token, which the admin pipeline's `RequireSudo` plug demands. Use for
  requests through the sudo-gated admin routes. JWT auth alone leaves no
  `oauth_tokens` row, so persist one — mirroring an admin who just
  completed the password + TOTP step-up.
  """
  def admin_conn(conn, identity) do
    {:ok, token, _} = Token.generate_access_token(identity.id)
    now = DateTime.utc_now()

    %OAuthToken{}
    |> OAuthToken.changeset(%{
      identity_id: identity.id,
      token_hash: Token.hash_token(token),
      scopes: ["read", "write"],
      expires_at: DateTime.add(now, 3600, :second),
      sudo_until: DateTime.add(now, 3600, :second)
    })
    |> Repo.insert!()

    Plug.Conn.put_req_header(conn, "authorization", "Bearer #{token}")
  end

  defp register(handle, email) do
    {:ok, identity} =
      Accounts.register_user(%{
        "handle" => handle,
        "email" => email || "#{handle}@test.com",
        "password" => @password,
        "password_confirmation" => @password
      })

    identity
  end
end
