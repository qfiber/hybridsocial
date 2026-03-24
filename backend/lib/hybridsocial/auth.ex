defmodule Hybridsocial.Auth do
  @moduledoc """
  Authentication context. Handles login, token management, and session lifecycle.
  """
  alias Hybridsocial.Repo
  alias Hybridsocial.Accounts
  alias Hybridsocial.Accounts.User
  alias Hybridsocial.Auth.Token
  alias Hybridsocial.Auth.OAuthToken

  import Ecto.Query

  def login(email, password) do
    with {:ok, user} <- Accounts.authenticate_user(email, password) do
      if user.otp_enabled do
        {:error, :otp_required, user.identity_id}
      else
        issue_tokens(user)
      end
    end
  end

  def login_with_otp(identity_id, code) do
    with {:ok, user} <- Accounts.verify_2fa(identity_id, code) do
      user = Repo.preload(user, :identity)
      issue_tokens(user)
    end
  end

  defp issue_tokens(user, session_info \\ %{}) do
    with {:ok, access_token, _claims} <- Token.generate_access_token(user.identity_id),
         {refresh_token, refresh_hash} <- Token.generate_refresh_token(),
         {:ok, _oauth_token} <-
           create_token_record(user.identity_id, access_token, refresh_hash, session_info) do
      # Update last login
      user |> User.login_changeset() |> Repo.update()

      {:ok,
       %{
         access_token: access_token,
         refresh_token: refresh_token,
         token_type: "Bearer",
         expires_in: Token.access_token_ttl(),
         identity_id: user.identity_id
       }}
    end
  end

  @doc "Login with session metadata (IP, user agent)."
  def login_with_session(email, password, session_info) do
    with {:ok, user} <- Accounts.authenticate_user(email, password) do
      if user.otp_enabled do
        {:error, :otp_required, user.identity_id}
      else
        issue_tokens(user, session_info)
      end
    end
  end

  def login_with_otp_session(identity_id, code, session_info) do
    with {:ok, user} <- Accounts.verify_2fa(identity_id, code) do
      user = Repo.preload(user, :identity)
      issue_tokens(user, session_info)
    end
  end

  def refresh(refresh_token, session_info \\ %{}) do
    refresh_hash = Token.hash_token(refresh_token)

    case get_valid_token_by_refresh(refresh_hash) do
      nil ->
        {:error, :invalid_refresh_token}

      oauth_token ->
        # Revoke old token
        revoke_token(oauth_token)

        # Generate new pair, carry forward session info from old token
        merged_info = %{
          ip_address: session_info[:ip_address] || oauth_token.ip_address,
          user_agent: session_info[:user_agent] || oauth_token.user_agent,
          device_name: oauth_token.device_name
        }

        with {:ok, access_token, _claims} <- Token.generate_access_token(oauth_token.identity_id),
             {new_refresh, new_refresh_hash} <- Token.generate_refresh_token(),
             {:ok, _} <-
               create_token_record(
                 oauth_token.identity_id,
                 access_token,
                 new_refresh_hash,
                 merged_info
               ) do
          {:ok,
           %{
             access_token: access_token,
             refresh_token: new_refresh,
             token_type: "Bearer",
             expires_in: Token.access_token_ttl(),
             identity_id: oauth_token.identity_id
           }}
        end
    end
  end

  def logout(access_token) do
    token_hash = Token.hash_token(access_token)

    case get_token_by_hash(token_hash) do
      nil -> {:ok, :logged_out}
      oauth_token -> revoke_token(oauth_token)
    end
  end

  # ---- Session management ----

  @doc "List all active sessions for an identity. Current session first, then by most recent activity."
  def list_sessions(identity_id) do
    OAuthToken
    |> where([t], t.identity_id == ^identity_id and is_nil(t.revoked_at))
    |> order_by([t], desc_nulls_last: t.last_active_at)
    |> Repo.all()
  end

  @doc "Revoke a specific session by token ID."
  def revoke_session(identity_id, token_id) do
    case Repo.get(OAuthToken, token_id) do
      nil ->
        {:error, :not_found}

      %OAuthToken{identity_id: ^identity_id} = token ->
        revoke_token(token)

      _ ->
        {:error, :not_found}
    end
  end

  @doc "Revoke all sessions except the current one."
  def revoke_other_sessions(identity_id, current_token) do
    current_hash = Token.hash_token(current_token)

    {count, _} =
      OAuthToken
      |> where(
        [t],
        t.identity_id == ^identity_id and
          is_nil(t.revoked_at) and
          t.token_hash != ^current_hash
      )
      |> Repo.update_all(set: [revoked_at: DateTime.utc_now()])

    {:ok, count}
  end

  @doc "Update last_active_at for a token (called from auth plug)."
  def touch_session(token_hash, ip_address \\ nil) do
    now = DateTime.utc_now()

    updates = [last_active_at: now]
    updates = if ip_address, do: [{:ip_address, ip_address} | updates], else: updates

    OAuthToken
    |> where([t], t.token_hash == ^token_hash and is_nil(t.revoked_at))
    |> Repo.update_all(set: updates)

    :ok
  end

  # ---- Private ----

  @max_sessions_per_user 50

  defp create_token_record(identity_id, access_token, refresh_hash, session_info) do
    token_hash = Token.hash_token(access_token)
    expires_at = DateTime.add(DateTime.utc_now(), Token.access_token_ttl(), :second)
    now = DateTime.utc_now()

    device_name = session_info[:device_name] || parse_device_name(session_info[:user_agent])

    result =
      %OAuthToken{}
      |> OAuthToken.changeset(%{
        identity_id: identity_id,
        token_hash: token_hash,
        refresh_token_hash: refresh_hash,
        scopes: ["read", "write"],
        expires_at: expires_at,
        ip_address: session_info[:ip_address],
        user_agent: session_info[:user_agent],
        device_name: device_name,
        last_active_at: now
      })
      |> Repo.insert()

    # Enforce session cap — revoke oldest sessions beyond the limit
    enforce_session_limit(identity_id)

    # Clean up old revoked tokens
    cleanup_revoked_tokens(identity_id)

    result
  end

  defp enforce_session_limit(identity_id) do
    active_count =
      OAuthToken
      |> where([t], t.identity_id == ^identity_id and is_nil(t.revoked_at))
      |> Repo.aggregate(:count)

    if active_count > @max_sessions_per_user do
      # Revoke the oldest sessions beyond the limit
      excess = active_count - @max_sessions_per_user

      oldest_ids =
        OAuthToken
        |> where([t], t.identity_id == ^identity_id and is_nil(t.revoked_at))
        |> order_by([t], asc: t.last_active_at)
        |> limit(^excess)
        |> select([t], t.id)
        |> Repo.all()

      if oldest_ids != [] do
        OAuthToken
        |> where([t], t.id in ^oldest_ids)
        |> Repo.update_all(set: [revoked_at: DateTime.utc_now()])
      end
    end
  end

  defp cleanup_revoked_tokens(identity_id) do
    # Delete revoked tokens older than 30 days
    cutoff = DateTime.add(DateTime.utc_now(), -30 * 86400, :second)

    OAuthToken
    |> where(
      [t],
      t.identity_id == ^identity_id and
        not is_nil(t.revoked_at) and
        t.revoked_at < ^cutoff
    )
    |> Repo.delete_all()
  end

  defp get_valid_token_by_refresh(refresh_hash) do
    OAuthToken
    |> where([t], t.refresh_token_hash == ^refresh_hash and is_nil(t.revoked_at))
    |> Repo.one()
  end

  defp get_token_by_hash(token_hash) do
    OAuthToken
    |> where([t], t.token_hash == ^token_hash and is_nil(t.revoked_at))
    |> Repo.one()
  end

  defp revoke_token(oauth_token) do
    oauth_token
    |> OAuthToken.revoke_changeset()
    |> Repo.update()
  end

  @doc false
  def parse_device_name(nil), do: "Unknown device"

  def parse_device_name(ua) when is_binary(ua) do
    browser =
      cond do
        ua =~ ~r/Firefox/i -> "Firefox"
        ua =~ ~r/Edg/i -> "Edge"
        ua =~ ~r/OPR|Opera/i -> "Opera"
        ua =~ ~r/Chrome/i -> "Chrome"
        ua =~ ~r/Safari/i -> "Safari"
        ua =~ ~r/curl/i -> "curl"
        true -> "Browser"
      end

    os =
      cond do
        ua =~ ~r/Android/i -> "Android"
        ua =~ ~r/iPhone|iPad/i -> "iOS"
        ua =~ ~r/Mac OS/i -> "macOS"
        ua =~ ~r/Windows/i -> "Windows"
        ua =~ ~r/Linux/i -> "Linux"
        ua =~ ~r/CrOS/i -> "ChromeOS"
        true -> "Unknown"
      end

    "#{browser} on #{os}"
  end
end
