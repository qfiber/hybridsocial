defmodule Hybridsocial.Emails.Templates do
  @moduledoc """
  Admin-managed email templates. The catalog is authoritative — each
  entry declares its key, display name, the variables it accepts, and
  a sample-data map the admin preview uses. Keys that aren't in the
  catalog are rejected so an admin can't create arbitrary templates
  that no emitter ever reads.
  """

  alias Hybridsocial.Repo
  alias Hybridsocial.Emails.{Template, Defaults}

  # Each entry:
  #   key:         DB key + code-side identifier
  #   name:        shown in admin UI
  #   description: short hint in admin UI
  #   variables:   map of variable name => short description (for UI chips)
  #   sample:      preview data used by the admin "Preview" action
  @catalog [
    %{
      key: "confirmation",
      name: "Email confirmation",
      description: "Sent after registration with a link to verify the user's email.",
      variables: %{
        "instance_name" => "Instance display name",
        "user.display_name" => "Recipient's display name",
        "user.handle" => "Recipient's handle",
        "confirm_url" => "Absolute URL to the confirmation link"
      },
      sample: %{
        "instance_name" => "HybridSocial",
        "user" => %{"display_name" => "Sample User", "handle" => "sample"},
        "confirm_url" => "https://example.com/auth/confirm?token=abc123"
      }
    },
    %{
      key: "password_reset",
      name: "Password reset",
      description: "Sent when a user (or admin on their behalf) requests a password reset.",
      variables: %{
        "instance_name" => "Instance display name",
        "user.display_name" => "Recipient's display name",
        "user.handle" => "Recipient's handle",
        "reset_url" => "Absolute URL to the reset form"
      },
      sample: %{
        "instance_name" => "HybridSocial",
        "user" => %{"display_name" => "Sample User", "handle" => "sample"},
        "reset_url" => "https://example.com/auth/reset-password?token=abc123"
      }
    },
    %{
      key: "moderation_queue",
      name: "Moderation queue alert",
      description: "Alerts staff when a new item lands in the moderation queue.",
      variables: %{
        "instance_name" => "Instance display name",
        "item.item_type" => "Type of flagged item (post, account, etc.)",
        "item.severity" => "low / medium / high",
        "item.source" => "Where the flag came from",
        "item.reason" => "Why it was flagged",
        "queue_url" => "Absolute URL to the admin queue"
      },
      sample: %{
        "instance_name" => "HybridSocial",
        "item" => %{
          "item_type" => "post",
          "severity" => "high",
          "source" => "content filter",
          "reason" => "matched the `spam-url` rule"
        },
        "queue_url" => "https://example.com/admin/moderation-queue"
      }
    },
    %{
      key: "login_notification",
      name: "New login notification",
      description: "Alerts a user to a new sign-in from an unfamiliar device or location.",
      variables: %{
        "instance_name" => "Instance display name",
        "user.display_name" => "Recipient's display name",
        "ip" => "IP address of the login",
        "user_agent" => "Browser / app identifier"
      },
      sample: %{
        "instance_name" => "HybridSocial",
        "user" => %{"display_name" => "Sample User", "handle" => "sample"},
        "ip" => "203.0.113.42",
        "user_agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"
      }
    },
    %{
      key: "account_approved",
      name: "Account approved",
      description: "Sent when an admin approves a pending account (approval registration mode).",
      variables: %{
        "instance_name" => "Instance display name",
        "user.display_name" => "Recipient's display name",
        "user.handle" => "Recipient's handle",
        "login_url" => "Absolute URL to the login page"
      },
      sample: %{
        "instance_name" => "HybridSocial",
        "user" => %{"display_name" => "Sample User", "handle" => "sample"},
        "login_url" => "https://example.com/login"
      }
    },
    %{
      key: "appeal_approved",
      name: "Appeal approved",
      description: "Sent when an admin approves a user's appeal and reverses the action.",
      variables: %{
        "instance_name" => "Instance display name",
        "user.display_name" => "Recipient's display name",
        "user.handle" => "Recipient's handle",
        "appeal.action_type" => "The action that was reversed (suspend, silence, warn…)",
        "response" => "Admin's free-text reply (may be empty)",
        "app_url" => "Absolute URL back to the app"
      },
      sample: %{
        "instance_name" => "HybridSocial",
        "user" => %{"display_name" => "Sample User", "handle" => "sample"},
        "appeal" => %{"action_type" => "suspend"},
        "response" =>
          "You're right — the flag was from a misconfigured filter. We've removed the suspension.",
        "app_url" => "https://example.com"
      }
    },
    %{
      key: "appeal_rejected",
      name: "Appeal rejected",
      description: "Sent when an admin rejects a user's appeal and the action stays in place.",
      variables: %{
        "instance_name" => "Instance display name",
        "user.display_name" => "Recipient's display name",
        "user.handle" => "Recipient's handle",
        "appeal.action_type" => "The action that stays in place",
        "response" => "Admin's free-text reply (may be empty)",
        "contact_email" => "Instance contact email"
      },
      sample: %{
        "instance_name" => "HybridSocial",
        "user" => %{"display_name" => "Sample User", "handle" => "sample"},
        "appeal" => %{"action_type" => "suspend"},
        "response" => "The behavior you've described still violates our rules.",
        "contact_email" => "admin@example.com"
      }
    },
    %{
      key: "account_rejected",
      name: "Account rejected",
      description:
        "Sent when an admin rejects a pending account. Optional — leave disabled if you'd rather not notify.",
      variables: %{
        "instance_name" => "Instance display name",
        "user.display_name" => "Recipient's display name",
        "user.handle" => "Recipient's handle",
        "reason" => "Optional admin-supplied reason (may be empty)",
        "contact_email" => "Instance contact email for appeals"
      },
      sample: %{
        "instance_name" => "HybridSocial",
        "user" => %{"display_name" => "Sample User", "handle" => "sample"},
        "reason" => "The handle matches a banned pattern.",
        "contact_email" => "admin@example.com"
      }
    },
    %{
      key: "admin_pending_account",
      name: "Admin: new pending account",
      description:
        "Sent to admins (with users.edit) when approval-mode registration creates a new pending user.",
      variables: %{
        "instance_name" => "Instance display name",
        "staff.display_name" => "Recipient admin's display name",
        "applicant.handle" => "Applicant's handle",
        "applicant.display_name" => "Applicant's display name",
        "applicant.email" => "Applicant's email",
        "approvals_url" => "Absolute URL to /admin/approvals"
      },
      sample: %{
        "instance_name" => "HybridSocial",
        "staff" => %{"display_name" => "Admin"},
        "applicant" => %{
          "handle" => "newuser",
          "display_name" => "New User",
          "email" => "new@example.com"
        },
        "approvals_url" => "https://example.com/admin/approvals"
      }
    },
    %{
      key: "admin_new_report",
      name: "Admin: new report",
      description:
        "Sent to staff with reports.manage when someone files a report, if report emails are turned on in Email Settings.",
      variables: %{
        "instance_name" => "Instance display name",
        "staff.display_name" => "Recipient admin's display name",
        "report.category" => "Category picked by the reporter",
        "report.target_type" => "post or identity",
        "report.reporter_handle" => "Who filed it",
        "report.reported_handle" => "Who they're reporting (may be blank for post-only)",
        "report.comment" => "Reporter's notes",
        "reports_url" => "Absolute URL to /admin/reports"
      },
      sample: %{
        "instance_name" => "HybridSocial",
        "staff" => %{"display_name" => "Admin"},
        "report" => %{
          "category" => "spam",
          "target_type" => "post",
          "reporter_handle" => "alice",
          "reported_handle" => "bob",
          "comment" => "Posting the same link in every thread."
        },
        "reports_url" => "https://example.com/admin/moderation?tab=reports"
      }
    },
    %{
      key: "admin_new_appeal",
      name: "Admin: new appeal",
      description: "Sent to admins (with users.manage) when a user appeals a moderation action.",
      variables: %{
        "instance_name" => "Instance display name",
        "staff.display_name" => "Recipient admin's display name",
        "appeal.identity_handle" => "Who filed the appeal",
        "appeal.action_type" => "The action being appealed (suspend, silence, warn…)",
        "appeal.reason" => "The user's reason",
        "appeals_url" => "Absolute URL to /admin/appeals"
      },
      sample: %{
        "instance_name" => "HybridSocial",
        "staff" => %{"display_name" => "Admin"},
        "appeal" => %{
          "identity_handle" => "alice",
          "action_type" => "suspend",
          "reason" => "I think this was a mistake — the bot flagged a quoted URL."
        },
        "appeals_url" => "https://example.com/admin/appeals"
      }
    },
    %{
      key: "admin_backup_failed",
      name: "Admin: backup failed",
      description:
        "Sent to admins (with backups.view) when a backup job ends in status=failed. Critical-ish; default throttle still applies.",
      variables: %{
        "instance_name" => "Instance display name",
        "staff.display_name" => "Recipient admin's display name",
        "backup.id" => "Backup job id",
        "backup.type" => "full / schema / etc.",
        "backup.started_at" => "When it started",
        "backups_url" => "Absolute URL to /admin/backups"
      },
      sample: %{
        "instance_name" => "HybridSocial",
        "staff" => %{"display_name" => "Admin"},
        "backup" => %{
          "id" => "00000000-0000-0000-0000-000000000000",
          "type" => "full",
          "started_at" => "2026-04-18T22:15:00Z"
        },
        "backups_url" => "https://example.com/admin/backups"
      }
    },
    %{
      key: "generic_notification",
      name: "In-app notification (email channel)",
      description:
        "Used whenever a user opted into email for a specific in-app notification type (follow, reply, mention, reaction, boost, …). Title and body come from the triggering event.",
      variables: %{
        "instance_name" => "Instance display name",
        "title" => "The notification's title line (e.g. \"@alice followed you\")",
        "body" => "Optional body / excerpt",
        "url" => "Link back into the app for this notification",
        "app_url" => "Absolute URL back to the app"
      },
      sample: %{
        "instance_name" => "HybridSocial",
        "title" => "@alice followed you",
        "body" => "",
        "url" => "https://example.com/notifications",
        "app_url" => "https://example.com"
      }
    },
    %{
      key: "notification_digest",
      name: "Notification digest",
      description: "Summarises recent in-app notifications for users who opted in.",
      variables: %{
        "instance_name" => "Instance display name",
        "user.display_name" => "Recipient's display name",
        "count" => "Number of notifications summarised",
        "summary_html" => "Pre-rendered HTML list of notifications",
        "app_url" => "Absolute URL back to the app"
      },
      sample: %{
        "instance_name" => "HybridSocial",
        "user" => %{"display_name" => "Sample User", "handle" => "sample"},
        "count" => 3,
        "summary_html" =>
          "<ul><li>@alice followed you</li><li>@bob replied to your post</li><li>@carol mentioned you</li></ul>",
        "app_url" => "https://example.com"
      }
    }
  ]

  @doc "Static catalog of editable templates."
  def catalog, do: @catalog

  def catalog_keys, do: Enum.map(@catalog, & &1.key)

  def catalog_entry(key) when is_binary(key) do
    Enum.find(@catalog, &(&1.key == key))
  end

  @doc "Returns stored overrides or nil per catalog key."
  def get(key) when is_binary(key), do: Repo.get(Template, key)

  @doc """
  Returns `{subject, html_body, enabled?}` from the stored override if
  present + enabled, else the hardcoded default shipped with the code.
  """
  def resolve(key) when is_binary(key) do
    case get(key) do
      %Template{enabled: true, subject: s, html_body: h} when is_binary(s) and is_binary(h) ->
        {s, h, true}

      _ ->
        {default_subject, default_html} = Defaults.for(key)
        {default_subject, default_html, false}
    end
  end

  @doc """
  Upsert an admin override. Sanitises the HTML aggressively and
  rejects unknown keys. The caller's identity_id is stamped on the
  row for audit purposes — same rationale as `created_by` on other
  admin-editable rows.
  """
  def upsert(key, attrs, updated_by) when is_binary(key) do
    if catalog_entry(key) == nil do
      {:error, :unknown_template}
    else
      sanitized =
        attrs
        |> Map.put("key", key)
        |> Map.put("updated_by", updated_by)
        |> Map.update("html_body", "", &sanitize_html/1)

      case get(key) do
        nil -> %Template{key: key}
        existing -> existing
      end
      |> Template.changeset(sanitized)
      |> Repo.insert_or_update()
    end
  end

  @doc "Remove the override entirely so the hardcoded default is used."
  def reset(key) when is_binary(key) do
    case get(key) do
      nil ->
        :ok

      template ->
        Repo.delete(template)
        |> case do
          {:ok, _} -> :ok
          err -> err
        end
    end
  end

  @doc "Returns admin-facing list: catalog merged with stored overrides."
  def list_for_admin do
    overrides = Template |> Repo.all() |> Map.new(&{&1.key, &1})

    Enum.map(@catalog, fn entry ->
      stored = Map.get(overrides, entry.key)
      {default_subject, default_html} = Defaults.for(entry.key)

      %{
        key: entry.key,
        name: entry.name,
        description: entry.description,
        variables: entry.variables,
        default_subject: default_subject,
        default_html: default_html,
        subject: (stored && stored.subject) || default_subject,
        html_body: (stored && stored.html_body) || default_html,
        enabled: stored == nil or stored.enabled,
        customized: stored != nil,
        updated_at: stored && stored.updated_at
      }
    end)
  end

  # HtmlSanitizeEx ships a strict scrubber that drops <script>,
  # <iframe>, event handlers, and javascript: URLs — all the things we
  # don't want an admin to paste in and then broadcast to every user
  # via transactional email. `html5` keeps the tags we actually need
  # (div/p/a/img/table/style-attribute) for email styling.
  defp sanitize_html(html) when is_binary(html) do
    HtmlSanitizeEx.html5(html)
  end

  defp sanitize_html(_), do: ""
end
