defmodule Hybridsocial.Notifications.StaffEmail do
  @moduledoc """
  Generic fan-out for admin-targeted transactional emails. Finds
  every staff member that (a) holds any role, (b) has the required
  permission, and (c) has opted into the given notification key for
  email, then delivers a builder-produced Swoosh email to each one —
  once per throttle window per recipient.

  Throttle window is `moderation_email_throttle_seconds` (default
  600s); the same key that gates `moderation_queue` emails. We
  share it deliberately: a burst of reports shouldn't spam every
  admin either, and if an operator lowers the window they want it
  lowered uniformly.
  """

  require Logger
  import Ecto.Query

  alias Hybridsocial.{Accounts, Auth.IdentityRole, Auth.RBAC, Cache, Mailer, Notifications, Repo}
  alias Hybridsocial.Accounts.{Identity, User}

  @doc """
  `notification_key`: matches the `notification_preferences.type` a
  staff member must have set to email=true (e.g. `"admin_new_report"`).

  `required_permission`: RBAC permission the staff member must hold
  to be relevant for this event (e.g. `"reports.manage"`). Users
  without this permission are skipped — no point emailing them
  about something they can't act on.

  `build_email`: 2-arity fn `(to_email, identity) -> Swoosh.Email`.
  The identity is passed so the builder can personalize (use handle,
  display_name) and log failures against a recipient.

  Options:

    * `:default_email` - whether staff with no stored preference get this email
      (default `false`). They can still opt out with a stored preference.
    * `:throttle_seconds` - overrides the shared throttle window. `0` turns
      throttling off, so every event sends.
  """
  def dispatch(notification_key, required_permission, build_email, opts \\ [])
      when is_binary(notification_key) and is_binary(required_permission) and
             is_function(build_email, 2) do
    default_email = Keyword.get(opts, :default_email, false)
    throttle_sec = Keyword.get_lazy(opts, :throttle_seconds, &shared_throttle_seconds/0)

    staff_ids =
      from(r in IdentityRole,
        distinct: true,
        select: r.identity_id,
        where: is_nil(r.expires_at) or r.expires_at > ^DateTime.utc_now()
      )
      |> Repo.all()

    for identity_id <- staff_ids do
      if eligible?(identity_id, notification_key, required_permission, default_email) do
        maybe_send(identity_id, notification_key, throttle_sec, build_email)
      end
    end

    :ok
  end

  defp shared_throttle_seconds do
    case Hybridsocial.Config.get("moderation_email_throttle_seconds", 600) do
      n when is_integer(n) and n > 0 -> n
      _ -> 600
    end
  end

  defp eligible?(identity_id, notification_key, required_permission, default_email) do
    Notifications.email_enabled?(identity_id, notification_key, default_email) and
      RBAC.staff?(identity_id) and
      RBAC.has_permission?(identity_id, required_permission)
  end

  defp maybe_send(identity_id, notification_key, 0, build_email) do
    send_email(identity_id, notification_key, build_email)
  end

  defp maybe_send(identity_id, notification_key, throttle_sec, build_email) do
    # Scope the throttle per-recipient AND per-key, so getting a report
    # email doesn't suppress a backup-failure email from the same
    # window.
    throttle_key = "staff_email:#{notification_key}:#{identity_id}"

    case Cache.get(throttle_key) do
      nil ->
        # Set the flag BEFORE building the email. Two near-simultaneous
        # inserts from different processes would otherwise both race
        # past the check.
        Cache.set(throttle_key, "1", throttle_sec)
        send_email(identity_id, notification_key, build_email)

      _ ->
        :ok
    end
  end

  defp send_email(identity_id, notification_key, build_email) do
    with %Identity{} = identity <- Accounts.get_identity(identity_id),
         %User{email: email} when is_binary(email) and email != "" <-
           Accounts.get_user_by_identity(identity_id) do
      try do
        build_email.(email, identity) |> Mailer.deliver()
        audit(:delivered, identity_id, notification_key, email, nil)
      rescue
        e ->
          Logger.warning(
            "staff email #{notification_key} failed for #{identity_id}: #{Exception.message(e)}"
          )

          audit(:failed, identity_id, notification_key, nil, Exception.message(e))
      end
    end
  end

  # Leave a paper trail: staff fan-out is mostly invisible to admins,
  # but an auditor (or a staff member wondering "why did I get that
  # email?") should be able to reconstruct it. One row per recipient
  # per notification event.
  defp audit(outcome, identity_id, notification_key, email, error) do
    details =
      %{notification_key: notification_key, outcome: to_string(outcome)}
      |> maybe_put(:email, email)
      |> maybe_put(:error, error)

    Hybridsocial.Moderation.log(nil, "email.staff_notified", "identity", identity_id, details)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
