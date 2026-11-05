defmodule Hybridsocial.Emails do
  @moduledoc """
  Email builder module. Each function composes a Swoosh.Email for a
  specific transactional event, using `Hybridsocial.Emails.Renderer`
  to substitute variables into the (possibly admin-customised)
  template. Subjects and bodies live in `Emails.Defaults` as
  hardcoded fallbacks; admin overrides are stored in the
  `email_templates` table and merged transparently.
  """

  import Swoosh.Email

  alias Hybridsocial.Accounts.Identity
  alias Hybridsocial.Emails.Renderer
  alias Hybridsocial.Repo

  @default_from {"HybridSocial", "noreply@hybridsocial.local"}

  # ── Builders ──────────────────────────────────────────────────────

  @doc "Email confirmation with a token link."
  def confirmation_email(user) do
    assigns = %{
      "instance_name" => instance_name(),
      "user" => user_assigns(user),
      "confirm_url" => "#{base_url()}/auth/confirm?token=#{user.confirmation_token}"
    }

    render("confirmation", user, assigns)
  end

  @doc "Password reset with a token link."
  def password_reset_email(user) do
    assigns = %{
      "instance_name" => instance_name(),
      "user" => user_assigns(user),
      "reset_url" => "#{base_url()}/reset-password?token=#{user.reset_token}"
    }

    render("password_reset", user, assigns)
  end

  @doc """
  Alerts a staff member that a new item landed in the moderation
  queue. Throttled per-recipient by the caller.
  """
  def moderation_queue_email(to_email, _staff_identity, item) do
    assigns = %{
      "instance_name" => instance_name(),
      "item" => %{
        "item_type" => to_string(item.item_type),
        "severity" => to_string(item.severity || "medium"),
        "source" => to_string(item.source),
        "reason" => to_string(item.reason)
      },
      "queue_url" => "#{base_url()}/admin/moderation-queue"
    }

    {subject, html, text} =
      Renderer.render("moderation_queue", Map.merge(global_assigns(), assigns))

    new()
    |> to(to_email)
    |> from(from_address())
    |> subject(subject)
    |> html_body(html)
    |> text_body(text)
  end

  @doc "Login notification alerting the user of a new sign-in."
  def login_notification_email(user, ip, user_agent) do
    assigns = %{
      "instance_name" => instance_name(),
      "user" => user_assigns(user),
      "ip" => to_string(ip),
      "user_agent" => to_string(user_agent)
    }

    render("login_notification", user, assigns)
  end

  @doc "Sent when an admin approves a pending account."
  def account_approved_email(user) do
    assigns = %{
      "instance_name" => instance_name(),
      "user" => user_assigns(user),
      "login_url" => "#{base_url()}/login"
    }

    render("account_approved", user, assigns)
  end

  @doc """
  Sent when an admin rejects a pending account. `reason` is optional
  admin-supplied free text; it's escaped before substitution so an
  admin can't inject HTML into the recipient's inbox.
  """
  def account_rejected_email(user, reason \\ "") do
    assigns = %{
      "instance_name" => instance_name(),
      "user" => user_assigns(user),
      "reason" => (is_binary(reason) && reason != "" && reason) || "No reason provided.",
      "contact_email" => Hybridsocial.Config.get("contact_email", "")
    }

    render("account_rejected", user, assigns)
  end

  @doc """
  Sent to a content owner when staff remove their group/page/post/media/badge.
  `target_label` is a human word for the removed thing ("group", "post", …);
  `reason` is the moderator's free text (escaped); `appeal_days` is the window
  before permanent deletion.
  """
  def content_removed_email(user, opts \\ %{}) do
    assigns = %{
      "instance_name" => instance_name(),
      "user" => user_assigns(user),
      "target_label" => Map.get(opts, :target_label, "content"),
      "reason" => content_reason(Map.get(opts, :reason)),
      "appeal_days" => to_string(Map.get(opts, :appeal_days, 60))
    }

    render("content_removed", user, assigns)
  end

  defp content_reason(reason) when is_binary(reason) and reason != "", do: reason
  defp content_reason(_), do: "No reason provided."

  @doc """
  Final warning before a takedown is permanently deleted. `target_label` names
  the removed thing; `days_left` is how long is left to appeal.
  """
  def content_purge_reminder_email(user, opts \\ %{}) do
    assigns = %{
      "instance_name" => instance_name(),
      "user" => user_assigns(user),
      "target_label" => Map.get(opts, :target_label, "content"),
      "days_left" => to_string(Map.get(opts, :days_left, 0))
    }

    render("content_purge_reminder", user, assigns)
  end

  @doc "Sent to the appellant when their appeal is approved."
  def appeal_approved_email(user, appeal, response) do
    assigns = %{
      "instance_name" => instance_name(),
      "user" => user_assigns(user),
      "appeal" => %{"action_type" => to_string(appeal.action_type || "")},
      "response" => (is_binary(response) && response != "" && response) || "No note left.",
      "app_url" => base_url()
    }

    render("appeal_approved", user, assigns)
  end

  @doc "Sent to the appellant when their appeal is rejected."
  def appeal_rejected_email(user, appeal, response) do
    assigns = %{
      "instance_name" => instance_name(),
      "user" => user_assigns(user),
      "appeal" => %{"action_type" => to_string(appeal.action_type || "")},
      "response" => (is_binary(response) && response != "" && response) || "No note left.",
      "contact_email" => Hybridsocial.Config.get("contact_email", "")
    }

    render("appeal_rejected", user, assigns)
  end

  @doc "Admin-facing: new pending account awaiting approval."
  def admin_pending_account_email(to_email, staff_identity, applicant_identity, applicant_user) do
    assigns = %{
      "instance_name" => instance_name(),
      "staff" => user_assigns(staff_identity),
      "applicant" => %{
        "handle" => Map.get(applicant_identity, :handle) || "",
        "display_name" =>
          Map.get(applicant_identity, :display_name) || Map.get(applicant_identity, :handle) || "",
        "email" => Map.get(applicant_user, :email) || ""
      },
      "approvals_url" => "#{base_url()}/admin/approvals"
    }

    admin_render("admin_pending_account", to_email, assigns)
  end

  @doc "Admin-facing: new user report."
  def admin_new_report_email(to_email, staff_identity, report) do
    assigns = %{
      "instance_name" => instance_name(),
      "staff" => user_assigns(staff_identity),
      "report" => %{
        "category" => to_string(report.category || ""),
        "target_type" => to_string(report.target_type || ""),
        "reporter_handle" => (report.reporter && report.reporter.handle) || "",
        "reported_handle" => (report.reported && report.reported.handle) || "",
        # Reporter-supplied, and from any server for a federated report. The
        # renderer escapes it; the cap just keeps the email a sensible size.
        "comment" => report.description |> to_string() |> String.slice(0, 1000)
      },
      "reports_url" => "#{base_url()}/admin/moderation?tab=reports"
    }

    admin_render("admin_new_report", to_email, assigns)
  end

  @doc "Admin-facing: new appeal."
  def admin_new_appeal_email(to_email, staff_identity, appeal) do
    assigns = %{
      "instance_name" => instance_name(),
      "staff" => user_assigns(staff_identity),
      "appeal" => %{
        "identity_handle" => (appeal.identity && appeal.identity.handle) || "",
        "action_type" => to_string(appeal.action_type || ""),
        "reason" => to_string(appeal.reason || "")
      },
      "appeals_url" => "#{base_url()}/admin/appeals"
    }

    admin_render("admin_new_appeal", to_email, assigns)
  end

  @doc "Admin-facing: a backup job failed."
  def admin_backup_failed_email(to_email, staff_identity, backup) do
    assigns = %{
      "instance_name" => instance_name(),
      "staff" => user_assigns(staff_identity),
      "backup" => %{
        "id" => to_string(backup.id),
        "type" => to_string(Map.get(backup, :type) || ""),
        "started_at" => to_string(Map.get(backup, :started_at) || "")
      },
      "backups_url" => "#{base_url()}/admin/backups"
    }

    admin_render("admin_backup_failed", to_email, assigns)
  end

  @doc "Notification digest summarising recent notifications."
  def notification_digest_email(user, notifications) do
    count = length(notifications)
    summary_html = notifications_to_html(notifications)

    assigns = %{
      "instance_name" => instance_name(),
      "user" => user_assigns(user),
      "count" => count,
      # Pluralize the noun so a single-item digest reads "1 new
      # notification", not "1 new notifications".
      "noun" => if(count == 1, do: "notification", else: "notifications"),
      "summary_html" => summary_html,
      "app_url" => base_url()
    }

    render("notification_digest", user, assigns)
  end

  # ── Helpers ───────────────────────────────────────────────────────

  # User-targeted emails all share the same shape: recipient pulled
  # from the `user` struct, sender from instance settings, subject +
  # html + text from the Renderer.
  defp render(key, user, assigns) do
    {subject, html, text} = Renderer.render(key, Map.merge(global_assigns(), assigns))

    new()
    |> to({user_display_name(user), user_email(user)})
    |> from(from_address())
    |> subject(subject)
    |> html_body(html)
    |> text_body(text)
  end

  # Admin-facing emails route to an already-resolved staff email
  # address; we skip the user struct path because the recipient here
  # is chosen by `Notifications.StaffEmail.dispatch/3`, not by a
  # user-facing action.
  defp admin_render(key, to_email, assigns) do
    {subject, html, text} = Renderer.render(key, Map.merge(global_assigns(), assigns))

    new()
    |> to(to_email)
    |> from(from_address())
    |> subject(subject)
    |> html_body(html)
    |> text_body(text)
  end

  defp user_assigns(user) do
    identity = resolve_identity(user)

    %{
      "display_name" => user_display_name(user, identity),
      "handle" => user_handle(user, identity)
    }
  end

  # handle + display_name live on the Identity, but callers routinely pass the
  # User struct (e.g. the confirmation email fired right after registration, so
  # the account read `@!` with a blank handle). Resolve the backing identity
  # from an already-loaded assoc, an Identity struct, or a lookup by id.
  defp resolve_identity(%Identity{} = identity), do: identity
  defp resolve_identity(%{identity: %Identity{} = identity}), do: identity
  defp resolve_identity(%{identity_id: id}) when is_binary(id), do: Repo.get(Identity, id)
  defp resolve_identity(_), do: nil

  defp user_handle(user, identity) do
    cond do
      present?(identity && Map.get(identity, :handle)) -> identity.handle
      present?(Map.get(user, :handle)) -> Map.get(user, :handle)
      true -> ""
    end
  end

  defp present?(v), do: is_binary(v) and v != ""

  defp from_address do
    contact_email = Hybridsocial.Config.get("contact_email", "")
    instance_name = instance_name()

    if contact_email != "" do
      {instance_name, contact_email}
    else
      @default_from
    end
  end

  defp instance_name do
    Hybridsocial.Config.get("instance_name", "HybridSocial")
  end

  @doc """
  Variables injected into every email regardless of the emitter: the live
  instance name and the brand header (real logo or name text). Public so the
  admin preview can render templates with the instance's *actual* name and
  logo instead of placeholder sample data. `brand_header_html` ends in
  `_html`, so the renderer passes it through unescaped (server-built markup).
  """
  def global_assigns do
    %{
      "instance_name" => instance_name(),
      "brand_header_html" => brand_header_html()
    }
  end

  # Email header: the instance logo when an email-safe (raster) logo is
  # configured, else the instance name as text. Gmail/Outlook don't render
  # SVG, so an SVG site logo is skipped in favor of a PNG set via
  # `email_logo_url`.
  defp brand_header_html do
    name = instance_name()

    case email_logo_url() do
      url when is_binary(url) and url != "" ->
        ~s(<img src="#{url}" alt="#{escape_attr(name)}" height="48" style="height:48px;max-height:48px;width:auto;display:block;border:0;">)

      _ ->
        ~s(<div style="font-size:16px;font-weight:700;color:#6366f1;letter-spacing:0.02em;">#{escape_attr(name)}</div>)
    end
  end

  # Prefer a dedicated PNG email logo; otherwise reuse the site logo only if
  # it's a raster format email clients can actually display (not SVG). When the
  # site logo is an SVG and no PNG exists yet, self-heal: derive one in the
  # background so the next email carries the real logo. Fully automatic for any
  # instance — no hardcoded asset, no manual step.
  defp email_logo_url do
    case Hybridsocial.Config.get("email_logo_url", "") do
      url when is_binary(url) and url != "" ->
        url

      _ ->
        logo = Hybridsocial.Config.get("theme_logo_url", "")

        cond do
          not (is_binary(logo) and logo != "") -> nil
          String.ends_with?(String.downcase(logo), ".svg") -> self_heal_email_logo(logo)
          true -> logo
        end
    end
  end

  # Derive email_logo_url from the configured logo, once, off the request path.
  # Deduped via an atomic cache counter so a burst of emails spawns one job;
  # the lock expires so a failed derivation is retried on a later email.
  defp self_heal_email_logo(logo_url) do
    if Hybridsocial.Cache.increment("email_logo_selfheal", 600) == 1 do
      Task.Supervisor.start_child(Hybridsocial.TaskSupervisor, fn ->
        case Hybridsocial.Media.EmailLogo.derive_from_url(logo_url) do
          {:ok, url} -> Hybridsocial.Config.set("email_logo_url", url)
          _ -> :ok
        end
      end)
    end

    nil
  rescue
    _ -> nil
  end

  defp escape_attr(str) when is_binary(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp escape_attr(_), do: ""

  defp base_url do
    endpoint_config = Application.get_env(:hybridsocial, HybridsocialWeb.Endpoint, [])
    url_config = Keyword.get(endpoint_config, :url, [])
    host = Keyword.get(url_config, :host, "localhost")
    scheme = Keyword.get(url_config, :scheme, "https")
    port = Keyword.get(url_config, :port, 443)

    case {scheme, port} do
      {"https", 443} -> "#{scheme}://#{host}"
      {"http", 80} -> "#{scheme}://#{host}"
      _ -> "#{scheme}://#{host}:#{port}"
    end
  end

  defp user_display_name(user, identity \\ nil) do
    identity = identity || resolve_identity(user)

    cond do
      present?(identity && Map.get(identity, :display_name)) -> identity.display_name
      present?(identity && Map.get(identity, :handle)) -> identity.handle
      present?(Map.get(user, :display_name)) -> Map.get(user, :display_name)
      present?(Map.get(user, :handle)) -> Map.get(user, :handle)
      true -> "User"
    end
  end

  defp user_email(user), do: user.email

  defp notifications_to_html(notifications) do
    items =
      notifications
      |> Enum.map(fn n ->
        type = n[:type] || n["type"] || "unknown"
        "<li>#{escape(to_string(type))} notification</li>"
      end)
      |> Enum.join("")

    "<ul style=\"padding-left:20px;margin:0 0 16px 0;\">#{items}</ul>"
  end

  defp escape(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
