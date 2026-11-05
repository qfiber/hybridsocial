defmodule Hybridsocial.Emails.Defaults do
  @moduledoc """
  Hardcoded fallback subjects + HTML bodies for each template in the
  catalog. These ship with the code so a fresh instance has sane
  emails before any admin customises them, and so that resetting an
  override always has something to fall back to.

  Styles are **inlined** on purpose (Gmail drops `<style>` tags in
  the `<head>`, and we don't run a CSS inliner). Keep it that way when
  editing; the admin UI can use a CSS inliner client-side if desired
  but the defaults should not depend on one.

  Variables are `{{liquid-style}}` and resolved by `Emails.Renderer`.
  """

  # ── Public API ─────────────────────────────────────────────────────

  @doc "Returns `{subject, html}` for a catalog key."
  def for("confirmation"), do: {confirmation_subject(), confirmation_html()}
  def for("password_reset"), do: {password_reset_subject(), password_reset_html()}
  def for("moderation_queue"), do: {moderation_queue_subject(), moderation_queue_html()}
  def for("login_notification"), do: {login_notification_subject(), login_notification_html()}
  def for("notification_digest"), do: {notification_digest_subject(), notification_digest_html()}
  def for("account_approved"), do: {account_approved_subject(), account_approved_html()}
  def for("account_rejected"), do: {account_rejected_subject(), account_rejected_html()}
  def for("appeal_approved"), do: {appeal_approved_subject(), appeal_approved_html()}
  def for("appeal_rejected"), do: {appeal_rejected_subject(), appeal_rejected_html()}
  def for("content_removed"), do: {content_removed_subject(), content_removed_html()}

  def for("content_purge_reminder"),
    do: {content_purge_reminder_subject(), content_purge_reminder_html()}

  def for("admin_pending_account"),
    do: {admin_pending_account_subject(), admin_pending_account_html()}

  def for("admin_new_report"), do: {admin_new_report_subject(), admin_new_report_html()}
  def for("admin_new_appeal"), do: {admin_new_appeal_subject(), admin_new_appeal_html()}
  def for("admin_backup_failed"), do: {admin_backup_failed_subject(), admin_backup_failed_html()}

  def for("generic_notification"),
    do: {generic_notification_subject(), generic_notification_html()}

  def for(_), do: {"", ""}

  # ── Subjects ──────────────────────────────────────────────────────

  defp confirmation_subject, do: "{{instance_name}}: confirm your email address"
  defp password_reset_subject, do: "{{instance_name}}: reset your password"

  defp moderation_queue_subject,
    do:
      "{{instance_name}}: new {{item.severity}}-severity {{item.item_type}} in the moderation queue"

  defp login_notification_subject, do: "{{instance_name}}: new login to your account"

  defp notification_digest_subject,
    do: "{{instance_name}}: you have {{count}} new {{noun}}"

  defp account_approved_subject, do: "{{instance_name}}: your account is approved"
  defp account_rejected_subject, do: "{{instance_name}}: your account application"
  defp appeal_approved_subject, do: "{{instance_name}}: your appeal was approved"
  defp appeal_rejected_subject, do: "{{instance_name}}: your appeal"

  defp content_removed_subject,
    do: "{{instance_name}}: your {{target_label}} was removed"

  defp content_purge_reminder_subject,
    do: "{{instance_name}}: {{days_left}} days left to appeal your removed {{target_label}}"

  defp admin_pending_account_subject,
    do: "{{instance_name}}: new pending account @{{applicant.handle}}"

  defp admin_new_report_subject,
    do: "{{instance_name}}: new {{report.category}} report from @{{report.reporter_handle}}"

  defp admin_new_appeal_subject,
    do: "{{instance_name}}: new appeal from @{{appeal.identity_handle}}"

  defp admin_backup_failed_subject,
    do: "{{instance_name}}: backup failed ({{backup.type}})"

  defp generic_notification_subject, do: "{{title}}"

  # ── Shared layout helpers ─────────────────────────────────────────

  # Every default wraps content in this scaffold so the look is
  # consistent across emails. Admins can copy it verbatim into their
  # overrides or replace it entirely.
  defp layout(content_html, footer_note) do
    """
    <!DOCTYPE html>
    <html>
    <body style="margin:0;padding:0;background:#f4f4f6;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;color:#191c1d;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f4f4f6;padding:32px 16px;">
        <tr>
          <td align="center">
            <table role="presentation" width="560" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;background:#ffffff;border-radius:12px;box-shadow:0 1px 3px rgba(0,0,0,0.04);overflow:hidden;">
              <tr>
                <td style="padding:28px 32px 0 32px;">
                  {{brand_header_html}}
                </td>
              </tr>
              <tr>
                <td style="padding:16px 32px 32px 32px;font-size:15px;line-height:1.6;color:#191c1d;">
                  #{content_html}
                </td>
              </tr>
              <tr>
                <td style="padding:20px 32px 28px 32px;border-top:1px solid #e6e8eb;font-size:12px;line-height:1.5;color:#6b7280;">
                  #{footer_note}
                </td>
              </tr>
            </table>
          </td>
        </tr>
      </table>
    </body>
    </html>
    """
    |> String.trim()
  end

  defp button(label, url) do
    """
    <table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:24px 0;">
      <tr>
        <td style="border-radius:9999px;background:#6366f1;">
          <a href="#{url}" style="display:inline-block;padding:12px 24px;color:#ffffff;text-decoration:none;font-weight:600;font-size:14px;border-radius:9999px;">#{label}</a>
        </td>
      </tr>
    </table>
    """
  end

  # ── Per-template bodies ───────────────────────────────────────────

  defp confirmation_html do
    content = """
    <h1 style="margin:0 0 16px 0;font-size:22px;font-weight:700;">Welcome to {{instance_name}}, @{{user.handle}}!</h1>
    <p style="margin:0 0 8px 0;">Please confirm your email address so we can activate your account.</p>
    #{button("Confirm email", "{{confirm_url}}")}
    <p style="margin:0;font-size:13px;color:#6b7280;">Or copy and paste this link into your browser:<br>
    <a href="{{confirm_url}}" style="color:#6366f1;word-break:break-all;">{{confirm_url}}</a></p>
    """

    footer =
      "If you didn't create an account on {{instance_name}}, you can safely ignore this email."

    layout(content, footer)
  end

  defp password_reset_html do
    content = """
    <h1 style="margin:0 0 16px 0;font-size:22px;font-weight:700;">Reset your password</h1>
    <p style="margin:0 0 8px 0;">Hi @{{user.handle}}, we got a request to reset the password on your {{instance_name}} account.</p>
    #{button("Reset password", "{{reset_url}}")}
    <p style="margin:0 0 12px 0;font-size:13px;color:#6b7280;">The link expires in one hour.</p>
    <p style="margin:0;font-size:13px;color:#6b7280;">Or copy and paste this link into your browser:<br>
    <a href="{{reset_url}}" style="color:#6366f1;word-break:break-all;">{{reset_url}}</a></p>
    """

    footer =
      "If you didn't request this, someone may have typed your email by mistake, and it's safe to ignore this message."

    layout(content, footer)
  end

  defp moderation_queue_html do
    content = """
    <h1 style="margin:0 0 16px 0;font-size:20px;font-weight:700;">New item in the moderation queue</h1>
    <table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:8px 0 20px 0;font-size:14px;">
      <tr><td style="padding:4px 12px 4px 0;color:#6b7280;">Type</td><td style="padding:4px 0;">{{item.item_type}}</td></tr>
      <tr><td style="padding:4px 12px 4px 0;color:#6b7280;">Severity</td><td style="padding:4px 0;">{{item.severity}}</td></tr>
      <tr><td style="padding:4px 12px 4px 0;color:#6b7280;">Source</td><td style="padding:4px 0;">{{item.source}}</td></tr>
      <tr><td style="padding:4px 12px 4px 0;vertical-align:top;color:#6b7280;">Reason</td><td style="padding:4px 0;">{{item.reason}}</td></tr>
    </table>
    #{button("Review in queue", "{{queue_url}}")}
    """

    footer =
      "You're receiving this because the \"moderation_queue\" notification is enabled on your staff account. Turn it off anytime in your notification preferences."

    layout(content, footer)
  end

  defp login_notification_html do
    content = """
    <h1 style="margin:0 0 16px 0;font-size:20px;font-weight:700;">New sign-in to your account</h1>
    <p style="margin:0 0 16px 0;">Hi @{{user.handle}}, we noticed a new sign-in to your {{instance_name}} account.</p>
    <table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:8px 0 20px 0;font-size:14px;">
      <tr><td style="padding:4px 12px 4px 0;color:#6b7280;">IP address</td><td style="padding:4px 0;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;">{{ip}}</td></tr>
      <tr><td style="padding:4px 12px 4px 0;vertical-align:top;color:#6b7280;">Device</td><td style="padding:4px 0;">{{user_agent}}</td></tr>
    </table>
    <p style="margin:0;">If this was you, no action is needed. If it wasn't, change your password immediately and revoke your sessions.</p>
    """

    footer =
      "You're receiving this because login alerts are enabled on your account."

    layout(content, footer)
  end

  defp notification_digest_html do
    content = """
    <h1 style="margin:0 0 16px 0;font-size:20px;font-weight:700;">Your {{instance_name}} digest</h1>
    <p style="margin:0 0 16px 0;">Hi @{{user.handle}}, you have {{count}} new {{noun}}:</p>
    {{summary_html}}
    #{button("Open {{instance_name}}", "{{app_url}}")}
    """

    footer =
      "You're receiving this digest because you opted in under notification preferences. You can turn it off anytime."

    layout(content, footer)
  end

  defp account_approved_html do
    content = """
    <h1 style="margin:0 0 16px 0;font-size:22px;font-weight:700;">You're in, @{{user.handle}}!</h1>
    <p style="margin:0 0 8px 0;">An admin has approved your {{instance_name}} account. You can log in and start posting right now.</p>
    #{button("Log in", "{{login_url}}")}
    <p style="margin:0;font-size:13px;color:#6b7280;">Welcome aboard.</p>
    """

    footer =
      "You're receiving this because you applied for an account on {{instance_name}}."

    layout(content, footer)
  end

  defp account_rejected_html do
    content = """
    <h1 style="margin:0 0 16px 0;font-size:20px;font-weight:700;">Your account application</h1>
    <p style="margin:0 0 12px 0;">Hi {{user.display_name}},</p>
    <p style="margin:0 0 12px 0;">Thanks for your interest in {{instance_name}}. After review, we weren't able to approve your account at this time.</p>
    <p style="margin:0 0 12px 0;"><strong>Reason:</strong> {{reason}}</p>
    <p style="margin:0;">If you believe this was a mistake, reply to this email or contact <a href="mailto:{{contact_email}}" style="color:#6366f1;">{{contact_email}}</a>.</p>
    """

    footer =
      "You're receiving this because you applied for an account on {{instance_name}}."

    layout(content, footer)
  end

  defp content_removed_html do
    content = """
    <h1 style="margin:0 0 16px 0;font-size:20px;font-weight:700;">Your {{target_label}} was removed</h1>
    <p style="margin:0 0 12px 0;">Hi {{user.display_name}},</p>
    <p style="margin:0 0 12px 0;">A moderator on {{instance_name}} removed your {{target_label}} because it was found to violate our rules.</p>
    <p style="margin:0 0 12px 0;"><strong>Reason:</strong> {{reason}}</p>
    <p style="margin:0 0 12px 0;">If you believe this was a mistake, or you can explain the situation and confirm it won't happen again, you can appeal and ask for it to be restored. <strong>You have {{appeal_days}} days to appeal.</strong> After that the content is permanently deleted and can't be recovered.</p>
    #{button("Appeal this removal", "{{app_url}}/appeals")}
    <p style="margin:0;font-size:13px;color:#6b7280;">Please review the community rules before appealing so the same issue doesn't recur.</p>
    """

    footer =
      "You're receiving this because content you own was moderated on {{instance_name}}."

    layout(content, footer)
  end

  defp content_purge_reminder_html do
    content = """
    <h1 style="margin:0 0 16px 0;font-size:20px;font-weight:700;">Last chance to appeal</h1>
    <p style="margin:0 0 12px 0;">Hi {{user.display_name}},</p>
    <p style="margin:0 0 12px 0;">Your {{target_label}} that was removed on {{instance_name}} is scheduled to be <strong>permanently deleted in {{days_left}} days</strong>. Once that happens it can't be recovered.</p>
    <p style="margin:0 0 12px 0;">If you'd like it restored, appeal now — explain the situation and confirm the issue won't recur.</p>
    #{button("Appeal now", "{{app_url}}/appeals")}
    <p style="margin:0;font-size:13px;color:#6b7280;">If you take no action, the content will be deleted for good.</p>
    """

    footer =
      "You're receiving this because content you own is about to be permanently deleted on {{instance_name}}."

    layout(content, footer)
  end

  defp appeal_approved_html do
    content = """
    <h1 style="margin:0 0 16px 0;font-size:22px;font-weight:700;">Good news, your appeal was approved</h1>
    <p style="margin:0 0 12px 0;">Hi @{{user.handle}}, we reviewed your appeal against the <strong>{{appeal.action_type}}</strong> action and decided to reverse it.</p>
    <p style="margin:0 0 12px 0;"><strong>Moderator's note:</strong> {{response}}</p>
    #{button("Back to {{instance_name}}", "{{app_url}}")}
    <p style="margin:0;font-size:13px;color:#6b7280;">Thanks for your patience.</p>
    """

    footer =
      "You're receiving this because you filed an appeal on {{instance_name}}."

    layout(content, footer)
  end

  defp appeal_rejected_html do
    content = """
    <h1 style="margin:0 0 16px 0;font-size:20px;font-weight:700;">Your appeal was reviewed</h1>
    <p style="margin:0 0 12px 0;">Hi @{{user.handle}}, we reviewed your appeal against the <strong>{{appeal.action_type}}</strong> action but decided to keep it in place.</p>
    <p style="margin:0 0 12px 0;"><strong>Moderator's note:</strong> {{response}}</p>
    <p style="margin:0;">If you'd like to discuss this further, reach out at <a href="mailto:{{contact_email}}" style="color:#6366f1;">{{contact_email}}</a>.</p>
    """

    footer =
      "You're receiving this because you filed an appeal on {{instance_name}}."

    layout(content, footer)
  end

  # ── Admin-facing emails ───────────────────────────────────────────

  defp admin_pending_account_html do
    content = """
    <h1 style="margin:0 0 16px 0;font-size:20px;font-weight:700;">New pending account</h1>
    <p style="margin:0 0 16px 0;">Hi {{staff.display_name}}, a new user is waiting for approval on {{instance_name}}.</p>
    <table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:0 0 20px 0;font-size:14px;">
      <tr><td style="padding:4px 12px 4px 0;color:#6b7280;">Handle</td><td style="padding:4px 0;">@{{applicant.handle}}</td></tr>
      <tr><td style="padding:4px 12px 4px 0;color:#6b7280;">Display name</td><td style="padding:4px 0;">{{applicant.display_name}}</td></tr>
      <tr><td style="padding:4px 12px 4px 0;color:#6b7280;">Email</td><td style="padding:4px 0;">{{applicant.email}}</td></tr>
    </table>
    #{button("Review in queue", "{{approvals_url}}")}
    """

    footer =
      "You're receiving this because \"admin_pending_account\" email notifications are enabled on your staff account. Turn it off anytime in your notification preferences."

    layout(content, footer)
  end

  defp admin_new_report_html do
    content = """
    <h1 style="margin:0 0 16px 0;font-size:20px;font-weight:700;">New report filed</h1>
    <p style="margin:0 0 16px 0;">Hi {{staff.display_name}}, a new report landed on {{instance_name}}.</p>
    <table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:0 0 20px 0;font-size:14px;">
      <tr><td style="padding:4px 12px 4px 0;color:#6b7280;">Category</td><td style="padding:4px 0;">{{report.category}}</td></tr>
      <tr><td style="padding:4px 12px 4px 0;color:#6b7280;">Target</td><td style="padding:4px 0;">{{report.target_type}}</td></tr>
      <tr><td style="padding:4px 12px 4px 0;color:#6b7280;">Reporter</td><td style="padding:4px 0;">@{{report.reporter_handle}}</td></tr>
      <tr><td style="padding:4px 12px 4px 0;color:#6b7280;">Reported</td><td style="padding:4px 0;">@{{report.reported_handle}}</td></tr>
      <tr><td style="padding:4px 12px 4px 0;vertical-align:top;color:#6b7280;">Comment</td><td style="padding:4px 0;">{{report.comment}}</td></tr>
    </table>
    #{button("Open reports queue", "{{reports_url}}")}
    """

    footer =
      "You're receiving this because report emails are turned on for {{instance_name}} and you can manage reports."

    layout(content, footer)
  end

  defp admin_new_appeal_html do
    content = """
    <h1 style="margin:0 0 16px 0;font-size:20px;font-weight:700;">New appeal filed</h1>
    <p style="margin:0 0 16px 0;">Hi {{staff.display_name}}, @{{appeal.identity_handle}} appealed a moderation action on {{instance_name}}.</p>
    <table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:0 0 20px 0;font-size:14px;">
      <tr><td style="padding:4px 12px 4px 0;color:#6b7280;">Action appealed</td><td style="padding:4px 0;">{{appeal.action_type}}</td></tr>
      <tr><td style="padding:4px 12px 4px 0;vertical-align:top;color:#6b7280;">Reason given</td><td style="padding:4px 0;">{{appeal.reason}}</td></tr>
    </table>
    #{button("Review appeal", "{{appeals_url}}")}
    """

    footer =
      "You're receiving this because \"admin_new_appeal\" email notifications are enabled on your staff account."

    layout(content, footer)
  end

  defp generic_notification_html do
    content = """
    <h1 style="margin:0 0 8px 0;font-size:18px;font-weight:700;">{{title}}</h1>
    <p style="margin:0 0 20px 0;color:#4b5563;">{{body}}</p>
    #{button("Open on {{instance_name}}", "{{url}}")}
    """

    footer =
      "You're receiving this because email delivery is enabled for this notification type on your account. Turn it off in your notification preferences."

    layout(content, footer)
  end

  defp admin_backup_failed_html do
    content = """
    <h1 style="margin:0 0 16px 0;font-size:20px;font-weight:700;color:#991b1b;">A backup job failed</h1>
    <p style="margin:0 0 16px 0;">Hi {{staff.display_name}}, a scheduled backup on {{instance_name}} did not complete successfully.</p>
    <table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:0 0 20px 0;font-size:14px;">
      <tr><td style="padding:4px 12px 4px 0;color:#6b7280;">Job id</td><td style="padding:4px 0;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;">{{backup.id}}</td></tr>
      <tr><td style="padding:4px 12px 4px 0;color:#6b7280;">Type</td><td style="padding:4px 0;">{{backup.type}}</td></tr>
      <tr><td style="padding:4px 12px 4px 0;color:#6b7280;">Started</td><td style="padding:4px 0;">{{backup.started_at}}</td></tr>
    </table>
    <p style="margin:0;font-size:14px;">Check server logs for the root cause (usually disk space, pg_dump version mismatch, or storage permissions).</p>
    #{button("Open backups", "{{backups_url}}")}
    """

    footer =
      "You're receiving this because \"admin_backup_failed\" email notifications are enabled on your staff account."

    layout(content, footer)
  end
end
