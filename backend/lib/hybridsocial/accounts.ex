defmodule Hybridsocial.Accounts do
  @moduledoc """
  The Accounts context. Manages identities, users, and organizations.
  """
  import Ecto.Query
  alias Hybridsocial.Repo
  alias Hybridsocial.Accounts.{Bot, Identity, Invite, User}

  @doc """
  Returns the bio rendered as safe HTML for display.

  Remote actors federate `summary` as HTML — we used to drop that
  HTML straight into the `bio` column and the frontend rendered it
  with text interpolation, so users saw literal `<br/>` / `<a>` /
  `&#39;` markup. Run remote bios through the basic scrubber so
  links and line breaks survive but scripts/iframes don't.

  Local bios are stored as plaintext (no markdown / HTML editor
  yet) — escape special chars and convert newlines to `<br>` so
  the same `{@html}` render path works for both.
  """
  def bio_html(%Identity{} = identity) do
    bio = identity.bio || ""

    cond do
      bio == "" ->
        ""

      remote_actor?(identity) or String.contains?(bio, "<") ->
        # Remote bios arrive as HTML; sanitize and ship.
        # Local bios with `<` shouldn't happen but defensively pass
        # them through the same scrubber so we never emit raw markup
        # we didn't approve.
        bio
        |> HtmlSanitizeEx.basic_html()
        |> harden_links()
        |> proxy_images()

      true ->
        bio
        |> escape_html()
        |> String.replace("\n", "<br>")
    end
  end

  def bio_html(_), do: ""

  defp escape_html(s) do
    s
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  # `HtmlSanitizeEx.basic_html` strips dangerous attributes and tags,
  # but it doesn't add the rel/target hardening every fediverse client
  # ships on user-content links: noopener (blocks reverse-tabnab via
  # window.opener), noreferrer (no Referer leak to the link target),
  # nofollow (PageRank hygiene for spam), ugc (Google's
  # user-generated-content marker), plus target=_blank so a malicious
  # bio link can't navigate the user away from the profile page.
  defp harden_links(html) do
    Regex.replace(~r/<a\b([^>]*)>/i, html, fn _full, attrs ->
      attrs = String.trim(attrs)
      attrs = Regex.replace(~r/\s+(target|rel)\s*=\s*"[^"]*"/i, attrs, "")
      attrs = if attrs == "", do: "", else: " " <> attrs
      "<a#{attrs} rel=\"nofollow noopener noreferrer ugc\" target=\"_blank\">"
    end)
  end

  # Route every external <img src> through our media proxy so a remote
  # bio can't drop a tracking pixel onto every viewer's browser. The
  # proxy fetches and caches the asset server-side, so the user's IP
  # never reaches the source host. `MediaProxy.url/1` is a no-op for
  # URLs already on our domain.
  defp proxy_images(html) do
    Regex.replace(~r/<img\b([^>]*?)\bsrc\s*=\s*"([^"]+)"([^>]*)>/i, html, fn _full,
                                                                             before_attrs,
                                                                             src,
                                                                             after_attrs ->
      proxied = Hybridsocial.Media.MediaProxy.url(src)
      "<img#{before_attrs} src=\"#{proxied}\"#{after_attrs}>"
    end)
  end

  # Authoritative via `is_local` — an imported legacy actor has a
  # foreign-shaped URL but is local, so the `/actors/` URL heuristic
  # would wrongly flag it remote.
  defp remote_actor?(%Identity{} = identity) do
    not Hybridsocial.Federation.LocalUrl.local_identity?(identity)
  end

  defp remote_actor?(_), do: false

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

  @doc """
  Fetches an identity including soft-deleted ones. Used where a deleted
  account must still resolve to a struct (e.g. rendering "Deleted User"
  for a former DM participant).
  """
  def get_identity_including_deleted(id), do: Repo.get(Identity, id)

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
    with :ok <- check_registration_open(),
         :ok <- check_pow(attrs),
         :ok <- check_captcha(attrs),
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
        # Send confirmation email with plaintext token for the link. Attach
        # the identity so the email renders @handle (handle lives on Identity,
        # not User — otherwise the welcome line reads "@!").
        email_user = %{
          user
          | confirmation_token: user.confirmation_token_plaintext,
            identity: identity
        }

        try do
          email_user
          |> Hybridsocial.Emails.confirmation_email()
          |> Hybridsocial.Mailer.deliver()
        rescue
          _ -> :ok
        end

        # In approval mode the new account sits pending until an admin
        # acts; let opted-in admins know there's something to review.
        # Fire-and-forget — the user's registration shouldn't fail if
        # SMTP is down.
        if Hybridsocial.Config.get("registration_mode", "open") == "approval" do
          Task.Supervisor.start_child(Hybridsocial.TaskSupervisor, fn ->
            Hybridsocial.Notifications.StaffEmail.dispatch(
              "admin_pending_account",
              "users.edit",
              fn to, staff_identity ->
                Hybridsocial.Emails.admin_pending_account_email(
                  to,
                  staff_identity,
                  identity,
                  user
                )
              end
            )
          end)
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

  @doc """
  Admin-driven account creation. Bypasses turnstile / PoW / invite-code /
  email-domain checks because the caller is trusted staff, not a public
  signup. No confirmation email is sent; pass `"auto_confirm" => true`
  in `attrs` to mark the new account's email confirmed immediately.

  Requires the standard registration changeset fields:
  `handle`, `email`, `password`, `password_confirmation`.
  Optional: `display_name`, `bio`, `auto_confirm`.
  """
  def admin_create_user(attrs) do
    auto_confirm = attrs["auto_confirm"] == true or attrs["auto_confirm"] == "true"

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:identity, fn _ ->
      %Identity{}
      |> Identity.create_changeset(Map.merge(attrs, %{"type" => "user"}))
    end)
    |> Ecto.Multi.insert(:user, fn %{identity: identity} ->
      %User{identity_id: identity.id}
      |> User.registration_changeset(attrs)
      |> maybe_mark_confirmed(auto_confirm)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{identity: identity, user: user}} ->
        identity = %{identity | user: user}
        Phoenix.PubSub.broadcast(Hybridsocial.PubSub, "identities", {:identity_created, identity})
        {:ok, identity}

      {:error, :identity, changeset, _} ->
        {:error, changeset}

      {:error, :user, changeset, _} ->
        {:error, changeset}
    end
  end

  defp maybe_mark_confirmed(changeset, false), do: changeset

  defp maybe_mark_confirmed(changeset, true) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    changeset
    |> Ecto.Changeset.put_change(:confirmed_at, now)
    |> Ecto.Changeset.put_change(:confirmation_token, nil)
  end

  @doc """
  Runs the PoW + captcha gates against a request's params, in that order.
  Shared by the public auth entry points (login, registration, recovery,
  password reset) so bot protection is enforced consistently. Returns `:ok`
  when both pass (or are disabled), else `{:error, :pow_required}` or a
  captcha error (`:captcha_failed` / `:missing_token` / …).
  """
  def check_bot_gates(attrs) do
    with :ok <- check_pow(attrs) do
      check_captcha(attrs)
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

  defp check_captcha(attrs) do
    if Hybridsocial.Auth.Captcha.enabled?() do
      # `captcha_token` is the provider-agnostic field; `cf_turnstile_token`
      # is kept for back-compat with clients built before the provider
      # selector existed.
      token = attrs["captcha_token"] || attrs["cf_turnstile_token"]

      case Hybridsocial.Auth.Captcha.verify(token) do
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

  # Backend-authoritative registration gate. "closed" rejects all signups
  # (the frontend also hides the form, but that isn't enforcement).
  defp check_registration_open do
    case Hybridsocial.Config.get("registration_mode", "open") do
      "closed" -> {:error, :registration_closed}
      _ -> :ok
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
    # Look up by the blind index — the email column itself is encrypted.
    hash = Hybridsocial.Crypto.blind_index(email, "user.email")

    User
    |> where([u], u.email_hash == ^hash)
    |> Repo.one()
    |> case do
      nil -> nil
      user -> Repo.preload(user, :identity)
    end
  end

  @doc """
  Look up a local user by their identity handle (username). Only local
  identities own a user row — remote actors fall through to nil, so they
  can't be logged into. Handles are globally unique in `identities`, so
  this resolves to at most one user.
  """
  def get_user_by_handle(handle) when is_binary(handle) do
    case get_identity_by_handle(handle) do
      nil ->
        nil

      identity ->
        User
        |> where([u], u.identity_id == ^identity.id)
        |> Repo.one()
        |> case do
          nil -> nil
          user -> Repo.preload(user, :identity)
        end
    end
  end

  def get_user_by_handle(_), do: nil

  # `identifier` is either an email or a handle (username) — the login
  # form accepts both. Email is tried first (the common case); a handle
  # input simply misses the email blind index and falls through.
  def authenticate_user(identifier, password) do
    case get_user_by_email(identifier) || get_user_by_handle(identifier) do
      nil ->
        # Prevent timing attacks
        Bcrypt.no_user_verify()
        {:error, :invalid_credentials}

      user ->
        cond do
          user.identity.is_suspended ->
            {:error, :account_suspended}

          user.identity.deleted_at ->
            {:error, :account_deleted}

          not Bcrypt.verify_pass(password, user.password_hash) ->
            {:error, :invalid_credentials}

          # Email confirmation gate. The instance config defaults to
          # `require_email_confirmation = true`, but the gate was
          # never wired into login — unconfirmed users could collect
          # tokens and use the platform as if confirmed. We only
          # enforce when the config is on, so an admin can still
          # disable confirmation site-wide.
          is_nil(user.confirmed_at) and Hybridsocial.Config.require_email_confirmation?() ->
            {:error, :email_not_confirmed, user.identity_id}

          true ->
            {:ok, user}
        end
    end
  end

  # --- Email confirmation ---

  @doc """
  Regenerates a confirmation token for an unconfirmed local account and
  re-sends the confirmation email. Non-committal: always returns `{:ok, :sent}`
  (a confirmed user or unknown email is a no-op) so it can't be used to probe
  which addresses have accounts. Abuse is bounded by the endpoint rate limit.
  """
  def resend_confirmation_email(email) when is_binary(email) and email != "" do
    case get_user_by_email(email) do
      %User{confirmed_at: nil} = user ->
        token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

        user
        |> Ecto.Changeset.change(%{
          confirmation_token: User.hash_token(token),
          confirmation_sent_at: DateTime.utc_now()
        })
        |> Repo.update()

        # Plaintext token rides the email link; the DB holds only the hash.
        email_user = %{user | confirmation_token: token}

        try do
          email_user
          |> Hybridsocial.Emails.confirmation_email()
          |> Hybridsocial.Mailer.deliver()
        rescue
          _ -> :ok
        end

        {:ok, :sent}

      _ ->
        {:ok, :sent}
    end
  end

  def resend_confirmation_email(_), do: {:ok, :sent}

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
        |> maybe_auto_approve()
        |> Repo.update()
    end
  end

  # When the instance does not require manual approval (any registration_mode
  # other than "approval"), a verified email is all that's needed — stamp
  # `approved_at` at confirmation time so the account isn't left sitting in the
  # admin approval queue. In "approval" mode we leave it for an admin to act.
  defp maybe_auto_approve(changeset) do
    if Hybridsocial.Config.get("registration_mode", "open") == "approval" do
      changeset
    else
      Ecto.Changeset.put_change(
        changeset,
        :approved_at,
        DateTime.utc_now() |> DateTime.truncate(:microsecond)
      )
    end
  end

  # --- Profile updates ---

  def update_identity(identity, attrs) do
    case identity |> Identity.update_changeset(attrs) |> Repo.update() do
      {:ok, updated} ->
        Phoenix.PubSub.broadcast(Hybridsocial.PubSub, "identities", {:identity_updated, updated})
        {:ok, updated}

      error ->
        error
    end
  end

  def admin_update_identity(identity, attrs) do
    case identity |> Identity.admin_update_changeset(attrs) |> Repo.update() do
      {:ok, updated} ->
        Phoenix.PubSub.broadcast(Hybridsocial.PubSub, "identities", {:identity_updated, updated})
        {:ok, updated}

      error ->
        error
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
    |> where(
      [i],
      i.parent_identity_id == ^parent_identity_id and i.type == ^type and is_nil(i.deleted_at)
    )
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

  defp subaccount_limit("organization"),
    do: Hybridsocial.Config.get("max_organizations_per_user", 2)

  defp subaccount_limit("group"), do: Hybridsocial.Config.get("max_groups_per_user", 4)
  defp subaccount_limit(_), do: 0

  @doc "Gets a subaccount identity, verifying it belongs to the parent."
  def get_subaccount(parent_identity_id, child_identity_id) do
    Identity
    |> where(
      [i],
      i.id == ^child_identity_id and i.parent_identity_id == ^parent_identity_id and
        is_nil(i.deleted_at)
    )
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
        Phoenix.PubSub.broadcast(
          Hybridsocial.PubSub,
          "identities",
          {:identity_deleted, deleted.id}
        )

        {:ok, deleted}

      {:error, :identity, changeset, _} ->
        {:error, changeset}

      {:error, _, reason, _} ->
        {:error, reason}
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
    |> Repo.preload(:user)
  end

  defp filter_by_type(query, nil), do: query
  defp filter_by_type(query, type), do: where(query, [i], i.type == ^type)

  defp filter_by_local(query, nil), do: query

  defp filter_by_local(query, true),
    do: where(query, [i], is_nil(i.ap_actor_url) or i.ap_actor_url == "")

  defp filter_by_local(query, false),
    do: where(query, [i], not is_nil(i.ap_actor_url) and i.ap_actor_url != "")

  # --- Password Reset ---

  # Map form (from the public endpoint): gate on PoW + captcha before doing
  # anything, so reset-email requests are as abuse-resistant as signup /
  # recovery. Returns {:error, :pow_required} / {:error, :captcha_failed}
  # when the gates aren't satisfied.
  def request_password_reset(attrs) when is_map(attrs) do
    with :ok <- check_pow(attrs),
         :ok <- check_captcha(attrs) do
      do_request_password_reset(attrs["email"])
    end
  end

  def request_password_reset(email) when is_binary(email) do
    do_request_password_reset(email)
  end

  defp do_request_password_reset(email) when is_binary(email) do
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

  # Missing/blank email — same non-committal response, no enumeration signal.
  defp do_request_password_reset(_), do: {:ok, :sent}

  def reset_password(token, password, password_confirmation) do
    hashed = User.hash_token(token)

    case Repo.one(from u in User, where: u.reset_token == ^hashed) do
      nil ->
        {:error, :invalid_token}

      user ->
        # Token lifetime is configurable (`password_reset_ttl_seconds`,
        # default 1 hour) so an onboarding/migration batch can issue
        # longer-lived links without weakening day-to-day resets.
        ttl =
          case Hybridsocial.Config.get("password_reset_ttl_seconds", 3600) do
            n when is_integer(n) and n > 0 -> n
            _ -> 3600
          end

        if DateTime.diff(DateTime.utc_now(), user.reset_token_at) > ttl do
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

  @doc """
  Admin-only: clears TOTP + recovery codes without requiring a
  current code. Used when a user is locked out and has asked staff
  to remove 2FA so they can log in again.
  """
  def admin_disable_2fa(identity_id) do
    case get_user(identity_id) do
      nil -> {:error, :not_found}
      user -> user |> User.otp_disable_changeset() |> Repo.update()
    end
  end

  @doc """
  Admin-only: marks a local user's email as confirmed without requiring
  them to click the link. Idempotent — returns `{:ok, :already_confirmed}`
  if the user was already confirmed. Returns `{:error, :not_found}` for
  remote identities or subaccounts that have no `users` row.
  """
  def admin_confirm_email(identity_id) do
    case get_user(identity_id) do
      nil ->
        {:error, :not_found}

      %User{confirmed_at: %DateTime{}} ->
        {:ok, :already_confirmed}

      user ->
        now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

        user
        |> Ecto.Changeset.change(%{confirmed_at: now, confirmation_token: nil})
        |> Repo.update()
    end
  end

  @doc """
  Admin-only: sends a password-reset email to a local user identified
  by identity_id. Unlike `request_password_reset/1` (the public-facing
  version, which intentionally swallows errors and always returns
  `:sent` to avoid leaking whether an email exists), this one surfaces
  real delivery failures — the admin needs to know whether the mail
  actually went out.

  Returns:
    * `{:ok, :sent}` — token generated and handed off to the Mailer.
    * `{:error, :not_found}` — no local user / no email on file.
    * `{:error, :email_not_configured}` — the Mailer is on the Local /
      Test adapter, which means the operator hasn't wired SMTP or
      Resend and the email would be silently discarded.
    * `{:error, {:delivery_failed, reason}}` — the adapter tried and
      returned an error.
  """
  def admin_send_password_reset_email(identity_id) do
    case get_user_by_identity(identity_id) do
      %User{email: email} = user when is_binary(email) and email != "" ->
        case check_email_configured() do
          :ok -> deliver_reset_email(user)
          {:error, _} = err -> err
        end

      _ ->
        {:error, :not_found}
    end
  end

  defp deliver_reset_email(user) do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    hashed = User.hash_token(token)

    user
    |> Ecto.Changeset.change(
      reset_token: hashed,
      reset_token_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
    )
    |> Repo.update()

    email_user = %{user | reset_token: token}

    case email_user
         |> Hybridsocial.Emails.password_reset_email()
         |> Hybridsocial.Mailer.deliver() do
      {:ok, _} -> {:ok, :sent}
      {:error, reason} -> {:error, {:delivery_failed, reason}}
    end
  end

  # The Local and Test adapters pretend to deliver but drop the mail on
  # the floor — treat them as "not configured" so the admin gets a
  # clear error instead of a misleading success.
  defp check_email_configured do
    case Application.get_env(:hybridsocial, Hybridsocial.Mailer, [])[:adapter] do
      Swoosh.Adapters.Local -> {:error, :email_not_configured}
      Swoosh.Adapters.Test -> {:error, :email_not_configured}
      nil -> {:error, :email_not_configured}
      _ -> :ok
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
          # Same email-confirmation gate as authenticate_user/2.
          # Otherwise a 2FA-protected unconfirmed account could
          # collect tokens via the OTP login route.
          if is_nil(user.confirmed_at) and Hybridsocial.Config.require_email_confirmation?() do
            {:error, :email_not_confirmed, user.identity_id}
          else
            {:ok, user}
          end
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
      nil ->
        {:error, :not_found}

      user ->
        user
        |> Ecto.Changeset.change(
          approved_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
        )
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
        |> User.email_changeset(new_email)
        |> Repo.update()
    end
  end

  # --- Change Email ---

  def change_email(identity_id, new_email, password) do
    with user when not is_nil(user) <- Repo.get_by(User, identity_id: identity_id),
         true <- Bcrypt.verify_pass(password, user.password_hash) do
      user
      |> User.email_changeset(new_email)
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

  # ---------------------------------------------------------------------------
  # Account recovery codes
  # ---------------------------------------------------------------------------

  alias Hybridsocial.Accounts.RecoveryCode

  @recovery_cooldown_seconds 24 * 3600

  @doc """
  Generate a new recovery code for the given identity. Requires the
  current password so an attacker with only a stolen session token
  can't lock out the real user. Returns `{:ok, plaintext_code, identity}`
  on success — the plaintext is shown to the user once and never
  persisted. Any previous code is invalidated.
  """
  def generate_recovery_code(identity_id, password)
      when is_binary(identity_id) and is_binary(password) do
    user = Repo.get_by(User, identity_id: identity_id)

    cond do
      is_nil(user) ->
        Bcrypt.no_user_verify()
        {:error, :not_found}

      not Bcrypt.verify_pass(password, user.password_hash) ->
        {:error, :invalid_password}

      user.otp_enabled != true ->
        {:error, :two_factor_required}

      true ->
        do_generate_recovery_code(identity_id)
    end
  end

  defp do_generate_recovery_code(identity_id) do
    case get_identity(identity_id) do
      nil ->
        {:error, :not_found}

      identity ->
        code = RecoveryCode.generate()
        hash = RecoveryCode.hash(code)
        now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

        case identity
             |> Ecto.Changeset.change(%{
               recovery_code_hash: hash,
               recovery_code_generated_at: now,
               recovery_code_last_used_at: nil
             })
             |> Repo.update() do
          {:ok, updated} -> {:ok, code, updated}
          other -> other
        end
    end
  end

  @doc """
  Clear the recovery code without replacing it. Requires current password.
  """
  def clear_recovery_code(identity_id, password) when is_binary(password) do
    with user when not is_nil(user) <- Repo.get_by(User, identity_id: identity_id),
         true <- Bcrypt.verify_pass(password, user.password_hash),
         identity when not is_nil(identity) <- get_identity(identity_id) do
      identity
      |> Ecto.Changeset.change(%{
        recovery_code_hash: nil,
        recovery_code_generated_at: nil,
        recovery_code_last_used_at: nil
      })
      |> Repo.update()
    else
      nil -> {:error, :not_found}
      false -> {:error, :invalid_password}
    end
  end

  @doc """
  Step 1 of account recovery: validate matching factors + anti-abuse.

  Matching factors (ALL must match): handle, recovery code, current
  TOTP code, current email. Also runs PoW and CAPTCHA gates when
  enabled in instance config.

  Returns `{:ok, identity}` when everything matches. The caller
  should then issue a short-lived signed token that allows step 2.

  Returns:
    * `{:error, :pow_required}` — PoW missing or invalid
    * `{:error, :captcha_failed}` / `{:error, :captcha_service_unavailable}` /
      `{:error, :captcha_parse_error}` / `{:error, :missing_token}` — captcha
    * `{:error, :invalid_credentials}` — any of the four factors didn't match
  """
  def validate_recovery_factors(params) when is_map(params) do
    handle = Map.get(params, "handle") || Map.get(params, :handle)
    code = Map.get(params, "recovery_code") || Map.get(params, :recovery_code)
    otp = Map.get(params, "otp_code") || Map.get(params, :otp_code)
    current_email = Map.get(params, "current_email") || Map.get(params, :current_email)

    required = [handle, code, otp, current_email]

    with false <- Enum.any?(required, &(not is_binary(&1))),
         :ok <- check_pow(params),
         :ok <- check_captcha(params),
         {:ok, identity} <- match_recovery_factors(handle, code, otp, current_email) do
      {:ok, identity}
    else
      true -> {:error, :invalid_credentials}
      {:error, _} = err -> err
    end
  end

  defp match_recovery_factors(handle, code, otp, current_email) do
    identity = get_identity_by_handle(handle)
    user = identity && Repo.get_by(User, identity_id: identity.id)

    code_ok? =
      case identity do
        %Identity{recovery_code_hash: hash} when is_binary(hash) ->
          RecoveryCode.verify(code, hash)

        _ ->
          RecoveryCode.verify(code, nil)
          false
      end

    otp_ok? =
      case user do
        %User{otp_enabled: true, otp_secret: encoded} when is_binary(encoded) ->
          case Base.decode32(encoded, padding: false) do
            {:ok, secret} -> Hybridsocial.Auth.TOTP.valid_code?(secret, otp)
            :error -> false
          end

        _ ->
          false
      end

    email_ok? =
      case user do
        %User{email: stored} when is_binary(stored) ->
          String.downcase(String.trim(current_email)) == String.downcase(stored)

        _ ->
          false
      end

    cond do
      not code_ok? -> {:error, :invalid_credentials}
      is_nil(user) -> {:error, :invalid_credentials}
      not otp_ok? -> {:error, :invalid_credentials}
      not email_ok? -> {:error, :invalid_credentials}
      true -> {:ok, identity}
    end
  end

  @doc """
  Step 2 of account recovery: apply the reset.

  Requires an identity previously validated via
  `validate_recovery_factors/1`. Resets password AND email, marks the
  account confirmed, revokes all sessions, stamps `recovered_at`
  (gates sensitive actions for 24h), auto-rotates the recovery code,
  and returns `{:ok, new_code, identity}`.

  Returns `{:error, :not_found}` if the identity or its user row no
  longer exists. Returns `{:error, :invalid_input, changeset}` when
  the new email/password fails validation.
  """
  def complete_recovery(identity_id, new_email, new_pw, new_pw_conf)
      when is_binary(identity_id) and is_binary(new_email) and is_binary(new_pw) and
             is_binary(new_pw_conf) do
    with identity when not is_nil(identity) <- get_identity(identity_id),
         user when not is_nil(user) <- Repo.get_by(User, identity_id: identity_id) do
      finalize_recovery(identity, user, new_email, new_pw, new_pw_conf)
    else
      nil -> {:error, :not_found}
    end
  end

  defp finalize_recovery(identity, user, new_email, new_pw, new_pw_conf) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    new_code = RecoveryCode.generate()
    new_hash = RecoveryCode.hash(new_code)

    Repo.transaction(fn ->
      # 1. Reset password, email, and mark account confirmed.
      case user
           |> User.password_changeset(%{
             "password" => new_pw,
             "password_confirmation" => new_pw_conf
           })
           |> Ecto.Changeset.cast(%{email: new_email}, [:email])
           |> Ecto.Changeset.validate_required([:email])
           |> Ecto.Changeset.validate_length(:email, max: 254)
           |> Ecto.Changeset.validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/)
           |> Ecto.Changeset.update_change(:email, &String.downcase/1)
           |> Ecto.Changeset.unique_constraint(:email)
           |> Ecto.Changeset.put_change(:confirmed_at, now)
           |> Ecto.Changeset.put_change(:reset_token, nil)
           |> Ecto.Changeset.put_change(:reset_token_at, nil)
           |> Repo.update() do
        {:ok, _user} -> :ok
        {:error, cs} -> Repo.rollback({:invalid_input, cs})
      end

      # 2. Rotate recovery code + stamp recovered_at.
      identity
      |> Ecto.Changeset.change(%{
        recovery_code_hash: new_hash,
        recovery_code_generated_at: now,
        recovery_code_last_used_at: now,
        recovered_at: now
      })
      |> Repo.update!()

      # 3. Revoke every existing session.
      revoke_all_tokens(identity.id)

      new_code
    end)
    |> case do
      {:ok, code} -> {:ok, code, Repo.get!(Identity, identity.id)}
      {:error, {:invalid_input, cs}} -> {:error, :invalid_input, cs}
      error -> error
    end
  end

  @doc """
  True when the identity is within the 24h post-recovery cooldown.
  Controllers gating sensitive actions (email change, profile changes,
  posts, DMs in strict mode) should call this and refuse if true.
  """
  def in_recovery_cooldown?(%Identity{recovered_at: nil}), do: false

  def in_recovery_cooldown?(%Identity{recovered_at: recovered_at}) do
    DateTime.diff(DateTime.utc_now(), recovered_at, :second) < @recovery_cooldown_seconds
  end

  def in_recovery_cooldown?(_), do: false
end
