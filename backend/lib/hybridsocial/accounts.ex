defmodule Hybridsocial.Accounts do
  @moduledoc """
  The Accounts context. Manages identities, users, and organizations.
  """
  import Ecto.Query
  alias Hybridsocial.Repo
  alias Hybridsocial.Accounts.{Bot, Identity, Invite, User}

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
         :ok <- check_handle_available(attrs),
         :ok <- check_invite_code(attrs) do
      result = do_register_user(attrs)

      # Consume the invite code on successful registration
      with {:ok, _identity} <- result,
           code when is_binary(code) <- attrs["invite_code"] do
        use_invite(code)
      end

      result
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

        identity = %{identity | user: user}
        Phoenix.PubSub.broadcast(Hybridsocial.PubSub, "identities", {:identity_created, identity})
        {:ok, identity}

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

        try do
          # Check the dedicated email_domain_bans table
          if Hybridsocial.Moderation.email_domain_banned?(domain) do
            {:error, :email_domain_banned}
          else
            # Also check the legacy banned_domains table with type "email"
            if function_exported?(Hybridsocial.Moderation, :domain_banned?, 2) and
                 Hybridsocial.Moderation.domain_banned?(domain, "email") do
              {:error, :email_domain_banned}
            else
              :ok
            end
          end
        rescue
          _ -> :ok
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

  defp check_invite_code(attrs) do
    reg_mode = Hybridsocial.Config.get("registration_mode", "open")

    if reg_mode == "invite_only" do
      case attrs["invite_code"] do
        nil ->
          {:error, :invite_required}

        code ->
          case validate_invite_code(code) do
            {:ok, _invite} -> :ok
            {:error, reason} -> {:error, reason}
          end
      end
    else
      :ok
    end
  end

  # --- Invite Codes ---

  @doc "Create a new invite code."
  def create_invite(attrs) do
    %Invite{}
    |> Invite.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc "List all invites."
  def list_invites do
    Invite
    |> order_by([i], desc: i.inserted_at)
    |> Repo.all()
    |> Repo.preload(:creator)
  end

  @doc "Disable an invite."
  def disable_invite(id) do
    case Repo.get(Invite, id) do
      nil -> {:error, :not_found}
      invite -> invite |> Ecto.Changeset.change(disabled: true) |> Repo.update()
    end
  end

  @doc "Delete an invite."
  def delete_invite(id) do
    case Repo.get(Invite, id) do
      nil -> {:error, :not_found}
      invite -> Repo.delete(invite)
    end
  end

  @doc "Validate and increment usage of an invite code."
  def use_invite(code) when is_binary(code) do
    case validate_invite_code(code) do
      {:ok, invite} ->
        invite
        |> Ecto.Changeset.change(uses: invite.uses + 1)
        |> Repo.update()

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Validate an invite code — checks existence, disabled, expiry, max uses."
  def validate_invite_code(code) when is_binary(code) do
    case Repo.one(from(i in Invite, where: i.code == ^code)) do
      nil ->
        {:error, :invalid_invite_code}

      %Invite{disabled: true} ->
        {:error, :invite_disabled}

      %Invite{expires_at: expires_at} = invite when not is_nil(expires_at) ->
        if DateTime.compare(DateTime.utc_now(), expires_at) == :gt do
          {:error, :invite_expired}
        else
          check_invite_uses(invite)
        end

      invite ->
        check_invite_uses(invite)
    end
  end

  defp check_invite_uses(%Invite{max_uses: nil} = invite), do: {:ok, invite}

  defp check_invite_uses(%Invite{uses: uses, max_uses: max_uses} = invite) do
    if uses >= max_uses do
      {:error, :invite_max_uses_reached}
    else
      {:ok, invite}
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
    case identity |> Identity.update_changeset(attrs) |> Repo.update() do
      {:ok, updated} ->
        Phoenix.PubSub.broadcast(Hybridsocial.PubSub, "identities", {:identity_updated, updated})
        {:ok, updated}
      error -> error
    end
  end

  def admin_update_identity(identity, attrs) do
    case identity |> Identity.admin_update_changeset(attrs) |> Repo.update() do
      {:ok, updated} ->
        Phoenix.PubSub.broadcast(Hybridsocial.PubSub, "identities", {:identity_updated, updated})
        {:ok, updated}
      error -> error
    end
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
    normalized = String.downcase(handle)

    # Check 1: Previously used handle (cooling-off period)
    history_reserved =
      Hybridsocial.Accounts.HandleHistory
      |> where([h], h.old_handle == ^handle and h.reserved_until > ^DateTime.utc_now())
      |> Repo.exists?()

    # Check 2: Admin-configured blocklist
    blocklist = Hybridsocial.Config.get("reserved_handles", [])

    blocklist_reserved =
      is_list(blocklist) and
        Enum.any?(blocklist, fn blocked ->
          String.downcase(to_string(blocked)) == normalized
        end)

    # Check 3: Short handle requires premium purchase
    short_handle_blocked = short_handle_restricted?(normalized)

    history_reserved or blocklist_reserved or short_handle_blocked
  end

  @doc "Check if a short handle requires premium purchase."
  def short_handle_restricted?(handle) do
    len = String.length(handle)

    cond do
      len == 1 and Hybridsocial.Config.get("premium_1char_handle_enabled", false) -> true
      len == 2 and Hybridsocial.Config.get("premium_2char_handle_enabled", false) -> true
      len == 3 and Hybridsocial.Config.get("premium_3char_handle_enabled", false) -> true
      true -> false
    end
  end

  # --- Suspension (with cascade to subaccounts) ---

  def suspend_identity(identity) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:identity, Identity.suspend_changeset(identity))
    |> Ecto.Multi.run(:cascade_children, fn _repo, _ ->
      cascade_suspend_children(identity.id)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{identity: identity}} -> {:ok, identity}
      {:error, :identity, changeset, _} -> {:error, changeset}
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  def unsuspend_identity(identity) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:identity, Identity.unsuspend_changeset(identity))
    |> Ecto.Multi.run(:cascade_children, fn _repo, _ ->
      cascade_unsuspend_children(identity.id)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{identity: identity}} -> {:ok, identity}
      {:error, :identity, changeset, _} -> {:error, changeset}
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  defp cascade_suspend_children(parent_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    {count, _} =
      Identity
      |> where([i], i.parent_identity_id == ^parent_id and is_nil(i.deleted_at))
      |> Repo.update_all(set: [is_suspended: true, suspended_at: now])

    {:ok, count}
  end

  defp cascade_unsuspend_children(parent_id) do
    {count, _} =
      Identity
      |> where([i], i.parent_identity_id == ^parent_id and is_nil(i.deleted_at))
      |> Repo.update_all(set: [is_suspended: false, suspended_at: nil])

    {:ok, count}
  end

  # --- Silencing ---

  def silence_identity(identity, attrs \\ %{}) do
    identity
    |> Identity.silence_changeset(attrs)
    |> Repo.update()
  end

  def unsilence_identity(identity) do
    identity
    |> Identity.unsilence_changeset()
    |> Repo.update()
  end

  # --- Shadow Banning ---

  def shadow_ban_identity(identity) do
    identity
    |> Identity.shadow_ban_changeset()
    |> Repo.update()
  end

  def unshadow_ban_identity(identity) do
    identity
    |> Identity.unshadow_ban_changeset()
    |> Repo.update()
  end

  # --- Sensitivity Forcing ---

  def force_sensitive_identity(identity) do
    identity
    |> Identity.force_sensitive_changeset()
    |> Repo.update()
  end

  def unforce_sensitive_identity(identity) do
    identity
    |> Identity.unforce_sensitive_changeset()
    |> Repo.update()
  end

  # --- Admin Token Revocation ---

  @doc "Revokes all active OAuth tokens for an identity. Used by admin actions."
  def admin_revoke_all_tokens(identity_id) do
    revoke_all_tokens(identity_id)
  end

  # --- Subaccounts ---

  @doc "Creates a bot subaccount under the given parent user identity."
  def create_bot(parent_identity_id, attrs) do
    with :ok <- check_subaccount_limit(parent_identity_id, "bot") do
      Ecto.Multi.new()
      |> Ecto.Multi.insert(:identity, fn _ ->
        %Identity{}
        |> Identity.create_changeset(%{
          "type" => "bot",
          "handle" => attrs["handle"],
          "display_name" => attrs["display_name"],
          "bio" => attrs["bio"],
          "parent_identity_id" => parent_identity_id,
          "is_bot" => true
        })
      end)
      |> Ecto.Multi.insert(:bot, fn %{identity: identity} ->
        %Bot{identity_id: identity.id}
        |> Bot.changeset(attrs)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{identity: identity, bot: bot}} ->
          {:ok, %{identity | bot: bot}}

        {:error, :identity, changeset, _} ->
          {:error, changeset}

        {:error, :bot, changeset, _} ->
          {:error, changeset}
      end
    end
  end

  @doc "Lists all subaccounts (children) of a parent identity."
  def list_subaccounts(parent_identity_id, opts \\ []) do
    type = Keyword.get(opts, :type)

    Identity
    |> where([i], i.parent_identity_id == ^parent_identity_id and is_nil(i.deleted_at))
    |> filter_by_type(type)
    |> order_by([i], asc: i.inserted_at)
    |> Repo.all()
  end

  @doc "Counts subaccounts of a given type for a parent identity."
  def count_subaccounts(parent_identity_id, type) do
    Identity
    |> where([i], i.parent_identity_id == ^parent_identity_id and i.type == ^type and is_nil(i.deleted_at))
    |> Repo.aggregate(:count)
  end

  @doc "Checks if the parent identity can create another subaccount of the given type."
  def check_subaccount_limit(parent_identity_id, type) do
    max = subaccount_limit(type)
    current = count_subaccounts(parent_identity_id, type)

    if current >= max do
      {:error, :subaccount_limit_reached}
    else
      :ok
    end
  end

  defp subaccount_limit("bot"), do: Hybridsocial.Config.get("max_bots_per_user", 4)
  defp subaccount_limit("organization"), do: Hybridsocial.Config.get("max_organizations_per_user", 2)
  defp subaccount_limit("group"), do: Hybridsocial.Config.get("max_groups_per_user", 4)
  defp subaccount_limit(_), do: 0

  @doc "Gets a subaccount identity, verifying it belongs to the parent."
  def get_subaccount(parent_identity_id, child_identity_id) do
    Identity
    |> where([i], i.id == ^child_identity_id and i.parent_identity_id == ^parent_identity_id and is_nil(i.deleted_at))
    |> Repo.one()
  end

  # --- Account deletion ---

  def soft_delete_identity(identity) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:identity, Identity.soft_delete_changeset(identity))
    |> Ecto.Multi.run(:cascade_children, fn _repo, _ ->
      cascade_soft_delete_children(identity.id)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{identity: deleted}} ->
        Phoenix.PubSub.broadcast(Hybridsocial.PubSub, "identities", {:identity_deleted, deleted.id})
        {:ok, deleted}
      {:error, :identity, changeset, _} -> {:error, changeset}
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  defp cascade_soft_delete_children(parent_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    {count, _} =
      Identity
      |> where([i], i.parent_identity_id == ^parent_id and is_nil(i.deleted_at))
      |> Repo.update_all(set: [deleted_at: now])

    {:ok, count}
  end

  # --- Listing ---

  def list_identities(opts \\ []) do
    Identity
    |> where([i], is_nil(i.deleted_at))
    |> filter_by_type(opts[:type])
    |> filter_by_local(opts[:local])
    |> order_by([i], desc: i.inserted_at)
    |> Repo.all()
  end

  defp filter_by_type(query, nil), do: query
  defp filter_by_type(query, type), do: where(query, [i], i.type == ^type)

  defp filter_by_local(query, nil), do: query
  defp filter_by_local(query, true), do: where(query, [i], is_nil(i.ap_actor_url) or i.ap_actor_url == "")
  defp filter_by_local(query, false), do: where(query, [i], not is_nil(i.ap_actor_url) and i.ap_actor_url != "")

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

  # --- Suggested Users ---

  def suggested_users(viewer_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    Identity
    |> where([i], i.is_suggested == true)
    |> where([i], is_nil(i.deleted_at) and i.is_suspended == false)
    |> where([i], i.id != ^viewer_id)
    |> order_by([i], desc: i.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  # --- Account Approval ---

  def pending_accounts do
    User
    |> where([u], not is_nil(u.confirmed_at) and is_nil(u.approved_at))
    |> join(:inner, [u], i in Identity, on: i.id == u.identity_id)
    |> select([u, i], %{user: u, identity: i})
    |> order_by([u], asc: u.confirmed_at)
    |> Repo.all()
  end

  def approve_account(identity_id) do
    case Repo.get_by(User, identity_id: identity_id) do
      nil -> {:error, :not_found}
      user ->
        user
        |> Ecto.Changeset.change(approved_at: DateTime.utc_now() |> DateTime.truncate(:microsecond))
        |> Repo.update()
    end
  end

  def reject_account(identity_id) do
    # Soft-delete the identity
    case get_identity(identity_id) do
      nil -> {:error, :not_found}
      identity -> soft_delete_identity(identity)
    end
  end

  # --- Public user access ---

  @doc "Gets the User record for an identity_id."
  def get_user_by_identity(identity_id) do
    User
    |> where([u], u.identity_id == ^identity_id)
    |> Repo.one()
  end

  # --- Admin force password reset ---

  @doc "Admin-only: sets a new password on the user, bypassing old password check."
  def admin_force_password(identity_id, new_password) do
    case Repo.get_by(User, identity_id: identity_id) do
      nil ->
        {:error, :not_found}

      user ->
        result =
          user
          |> User.password_changeset(%{
            "password" => new_password,
            "password_confirmation" => new_password
          })
          |> Repo.update()

        case result do
          {:ok, _} ->
            revoke_all_tokens(identity_id)
            result

          error ->
            error
        end
    end
  end

  # --- Admin change email ---

  @doc "Admin-only: changes a user's email, bypassing password verification."
  def admin_change_email(identity_id, new_email) do
    case Repo.get_by(User, identity_id: identity_id) do
      nil ->
        {:error, :not_found}

      user ->
        user
        |> Ecto.Changeset.change(email: new_email)
        |> Ecto.Changeset.validate_format(:email, ~r/@/)
        |> Ecto.Changeset.unique_constraint(:email)
        |> Repo.update()
    end
  end

  # --- Change Email ---

  def change_email(identity_id, new_email, password) do
    with user when not is_nil(user) <- Repo.get_by(User, identity_id: identity_id),
         true <- Bcrypt.verify_pass(password, user.password_hash) do
      user
      |> Ecto.Changeset.change(email: new_email)
      |> Ecto.Changeset.validate_format(:email, ~r/@/)
      |> Ecto.Changeset.unique_constraint(:email)
      |> Repo.update()
    else
      nil -> {:error, :not_found}
      false -> {:error, :invalid_password}
    end
  end

  # --- Account Migration ---

  def migrate_account(identity_id, target_acct, password) do
    with user when not is_nil(user) <- Repo.get_by(User, identity_id: identity_id),
         true <- Bcrypt.verify_pass(password, user.password_hash),
         identity when not is_nil(identity) <- get_identity(identity_id) do
      identity
      |> Ecto.Changeset.change(moved_to: target_acct)
      |> Repo.update()
    else
      nil -> {:error, :not_found}
      false -> {:error, :invalid_password}
    end
  end

  # --- Account Aliases ---

  def add_alias(identity, alias_uri) do
    current = identity.also_known_as || []
    if alias_uri in current do
      {:ok, identity}
    else
      identity
      |> Ecto.Changeset.change(also_known_as: current ++ [alias_uri])
      |> Repo.update()
    end
  end

  def remove_alias(identity, alias_uri) do
    current = identity.also_known_as || []
    identity
    |> Ecto.Changeset.change(also_known_as: Enum.reject(current, &(&1 == alias_uri)))
    |> Repo.update()
  end
end
