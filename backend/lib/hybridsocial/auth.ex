defmodule Hybridsocial.Auth do
  @moduledoc """
  Authentication context. Handles login, token management, and session lifecycle.
  """
  alias Hybridsocial.Repo
  alias Hybridsocial.Accounts
  alias Hybridsocial.Accounts.User
  alias Hybridsocial.Auth.Token
  alias Hybridsocial.Auth.OAuthToken
  alias Hybridsocial.Cache.TokenCache

  import Ecto.Query

  @doc """
  Whether an access token still backs a live session: a matching
  `oauth_tokens` row exists, is not revoked, and hasn't expired. This is
  what makes logout / revoke-session / revoke-all-devices actually take
  effect — the JWT alone can't be un-issued, so the auth plug consults
  this on top of JWT verification. Callers pass `Token.hash_token(token)`.
  """
  def access_token_active?(token_hash) when is_binary(token_hash) do
    active_session(token_hash) != nil
  end

  @doc """
  The live session behind an access token, or nil.

  Returns the grant the token carries — `application_id` (nil for a
  first-party session) and `scopes` — so the auth plug can enforce both
  revocation and scope from one lookup.
  """
  def active_session(token_hash) when is_binary(token_hash) do
    now = DateTime.utc_now()

    OAuthToken
    |> where([t], t.token_hash == ^token_hash)
    |> where([t], is_nil(t.revoked_at))
    |> where([t], t.expires_at > ^now)
    |> select([t], %{application_id: t.application_id, scopes: t.scopes})
    |> Repo.one()
  end

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

  def issue_tokens(user, session_info \\ %{}) do
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
    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        if user.otp_enabled do
          {:error, :otp_required, user.identity_id}
        else
          issue_tokens(user, session_info)
        end

      # Pass these through verbatim — the controller maps each one to
      # a distinct response shape (otp prompt, email-confirmation
      # nudge, etc.).
      other ->
        other
    end
  end

  def login_with_otp_session(identity_id, code, session_info) do
    case Accounts.verify_2fa(identity_id, code) do
      {:ok, user} ->
        user = Repo.preload(user, :identity)
        issue_tokens(user, session_info)

      # Pass through verbatim — controller distinguishes invalid OTP
      # from email-confirmation gating in its response shape.
      other ->
        other
    end
  end

  # Rotation grace: how long a just-rotated refresh token stays
  # honorable. Closes the cross-tab race where two contexts present
  # the same refresh token simultaneously — the second one used to
  # land on `invalid_refresh_token` and bounce the user to /login.
  @rotation_grace_seconds 30

  def refresh(refresh_token, session_info \\ %{}) do
    refresh_hash = Token.hash_token(refresh_token)

    case get_refreshable_token(refresh_hash) do
      nil ->
        {:error, :invalid_refresh_token}

      oauth_token ->
        # Stamp rotated_at instead of revoking — the token row stays
        # alive for `@rotation_grace_seconds` so a racing concurrent
        # refresh from another tab still lands on a valid record. A
        # third call after the grace window passes lapses naturally
        # (the WHERE clause in get_refreshable_token excludes it).
        mark_rotated(oauth_token)

        # Carry the still-valid sudo window forward so a token rotation
        # mid-session doesn't kick the operator out of the admin/mod
        # tools they just unlocked. If the previous token's sudo
        # window has already lapsed (or never existed), the new row
        # gets nil and the user re-confirms — same as before.
        carry_sudo_until =
          case oauth_token.sudo_until do
            %DateTime{} = until ->
              if DateTime.compare(until, DateTime.utc_now()) == :gt, do: until, else: nil

            _ ->
              nil
          end

        merged_info = %{
          ip_address: session_info[:ip_address] || oauth_token.ip_address,
          user_agent: session_info[:user_agent] || oauth_token.user_agent,
          device_name: oauth_token.device_name,
          sudo_until: carry_sudo_until
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

  # Acceptable for refresh: not revoked, and either never rotated or
  # rotated within the grace window.
  defp get_refreshable_token(refresh_hash) do
    cutoff = DateTime.add(DateTime.utc_now(), -@rotation_grace_seconds, :second)

    OAuthToken
    |> where([t], t.refresh_token_hash == ^refresh_hash)
    |> where([t], is_nil(t.revoked_at))
    |> where([t], is_nil(t.rotated_at) or t.rotated_at >= ^cutoff)
    |> Repo.one()
  end

  defp mark_rotated(oauth_token) do
    now = DateTime.utc_now()

    OAuthToken
    |> where([t], t.id == ^oauth_token.id)
    |> Repo.update_all(set: [rotated_at: now])
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
    # Only the *currently usable* tokens count as a session. A row
    # whose rotated_at has aged out of the grace window is dead even
    # though we never set revoked_at on it (the rotation grace lets
    # racing refreshes succeed without hard-revoking on rotation).
    grace_cutoff = DateTime.add(DateTime.utc_now(), -@rotation_grace_seconds, :second)

    OAuthToken
    |> where([t], t.identity_id == ^identity_id and is_nil(t.revoked_at))
    |> where([t], is_nil(t.rotated_at) or t.rotated_at >= ^grace_cutoff)
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

    {count, hashes} =
      OAuthToken
      |> where(
        [t],
        t.identity_id == ^identity_id and
          is_nil(t.revoked_at) and
          t.token_hash != ^current_hash
      )
      |> select([t], t.token_hash)
      |> Repo.update_all(set: [revoked_at: DateTime.utc_now()])

    # Invalidate each revoked token's session cache so "log out all
    # devices" takes effect immediately, not after the cache TTL.
    Enum.each(hashes || [], &TokenCache.invalidate_session/1)

    {:ok, count}
  end

  # ---- Sudo (step-up auth) ----
  #
  # Sudo mode is a short-lived flag on the token row that proves the
  # operator re-entered password + TOTP within the last N minutes. The
  # admin pipeline gates every write/read behind `sudo_until > now`.
  # The TTL is *rolling* — every successful admin request pushes the
  # expiry out by the same window, so active work doesn't get interrupted
  # but an idle tab times out.
  @sudo_ttl_seconds 30 * 60

  def sudo_ttl_seconds, do: @sudo_ttl_seconds

  @doc "Mark the given access token as sudo-elevated for `@sudo_ttl_seconds`."
  def grant_sudo(access_token) do
    token_hash = Token.hash_token(access_token)
    until = DateTime.add(DateTime.utc_now(), @sudo_ttl_seconds, :second)

    {count, _} =
      OAuthToken
      |> where([t], t.token_hash == ^token_hash and is_nil(t.revoked_at))
      |> Repo.update_all(set: [sudo_until: until])

    case count do
      0 -> {:error, :not_found}
      _ -> {:ok, until}
    end
  end

  @doc "Clear sudo elevation on the given access token."
  def revoke_sudo(access_token) do
    token_hash = Token.hash_token(access_token)

    OAuthToken
    |> where([t], t.token_hash == ^token_hash)
    |> Repo.update_all(set: [sudo_until: nil])

    :ok
  end

  @doc """
  Returns `{:ok, until}` if the token has a sudo window that hasn't lapsed,
  without moving it. Background polling uses this: a timer firing in an open
  tab isn't activity and mustn't keep the window alive.
  """
  def check_sudo(access_token) do
    case sudo_expires_at(access_token) do
      nil ->
        {:error, :sudo_required}

      until ->
        if DateTime.compare(until, DateTime.utc_now()) == :gt do
          {:ok, until}
        else
          {:error, :sudo_required}
        end
    end
  end

  @doc """
  Returns `{:ok, new_until}` if the token currently has a sudo window that
  hasn't lapsed, and extends it by the TTL (rolling window). Returns
  `{:error, :sudo_required}` otherwise.
  """
  def check_and_extend_sudo(access_token) do
    with {:ok, _until} <- check_sudo(access_token) do
      new_until = DateTime.add(DateTime.utc_now(), @sudo_ttl_seconds, :second)

      OAuthToken
      |> where([t], t.token_hash == ^Token.hash_token(access_token))
      |> Repo.update_all(set: [sudo_until: new_until])

      {:ok, new_until}
    end
  end

  @doc "Returns the current sudo expiry (or nil) for the given token."
  def sudo_expires_at(access_token) do
    token_hash = Token.hash_token(access_token)

    OAuthToken
    |> where([t], t.token_hash == ^token_hash and is_nil(t.revoked_at))
    |> select([t], t.sudo_until)
    |> Repo.one()
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
        last_active_at: now,
        # Refresh carries the still-valid sudo window forward; login
        # paths leave this as nil and the operator confirms when they
        # enter /admin or hit a sudo-gated route.
        sudo_until: session_info[:sudo_until]
      })
      |> Repo.insert()

    # Enforce session cap — revoke oldest sessions beyond the limit
    enforce_session_limit(identity_id)

    # Clean up old revoked tokens
    cleanup_revoked_tokens(identity_id)

    result
  end

  defp enforce_session_limit(identity_id) do
    grace_cutoff = DateTime.add(DateTime.utc_now(), -@rotation_grace_seconds, :second)

    active_query =
      OAuthToken
      |> where([t], t.identity_id == ^identity_id and is_nil(t.revoked_at))
      |> where([t], is_nil(t.rotated_at) or t.rotated_at >= ^grace_cutoff)

    active_count = Repo.aggregate(active_query, :count)

    if active_count > @max_sessions_per_user do
      excess = active_count - @max_sessions_per_user

      oldest_ids =
        active_query
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
    now = DateTime.utc_now()
    revoked_cutoff = DateTime.add(now, -30 * 86400, :second)
    rotated_cutoff = DateTime.add(now, -@rotation_grace_seconds, :second)

    # Two classes of dead tokens to sweep:
    # 1. Hard-revoked rows older than 30 days (logout / session
    #    revocation / session-cap eviction).
    # 2. Rotated rows past the grace window — these never get
    #    revoked_at set under the new refresh flow, so without this
    #    sweep they pile up on every refresh and surface as bogus
    #    "active" sessions in the user's session list.
    OAuthToken
    |> where(
      [t],
      t.identity_id == ^identity_id and
        ((not is_nil(t.revoked_at) and t.revoked_at < ^revoked_cutoff) or
           (not is_nil(t.rotated_at) and t.rotated_at < ^rotated_cutoff))
    )
    |> Repo.delete_all()
  end

  defp get_token_by_hash(token_hash) do
    OAuthToken
    |> where([t], t.token_hash == ^token_hash and is_nil(t.revoked_at))
    |> Repo.one()
  end

  defp revoke_token(oauth_token) do
    result =
      oauth_token
      |> OAuthToken.revoke_changeset()
      |> Repo.update()

    # Drop the positive session cache so the auth plug rejects this token
    # on the very next request (rather than waiting out the cache TTL).
    TokenCache.invalidate_session(oauth_token.token_hash)
    result
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
