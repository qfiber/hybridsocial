defmodule Hybridsocial.Moderation do
  @moduledoc """
  The Moderation context. Manages reports, audit log, content filters,
  banned domains, and moderation webhooks.
  """
  import Ecto.Query
  require Logger
  alias Hybridsocial.Repo

  alias Hybridsocial.Moderation.{
    Report,
    AuditLog,
    ContentFilter,
    BannedDomain,
    Webhook,
    WebhookDelivery,
    IpBan,
    EmailDomainBan,
    Appeal,
    ModerationNote,
    QueuedItem,
    MediaHashBan,
    BlockedHashtag,
    Takedown
  }

  alias Hybridsocial.Accounts.Identity

  # ── Reports ──────────────────────────────────────────────────────────

  def create_report(reporter_id, attrs) do
    result =
      %Report{}
      |> Report.changeset(attrs |> Map.put("reporter_id", reporter_id) |> force_instance_tier())
      |> Repo.insert()

    with {:ok, report} <- result do
      # Keep the denormalized open-report counter on posts in sync so
      # the admin moderation shield badge is O(1) to read on timeline
      # fetches. Non-post reports (account reports) are tracked via
      # the reports index and don't need the counter.
      if report.target_type == "post" and is_binary(report.target_id) do
        bump_post_open_report_count(report.target_id, 1)
      end
    end

    result
  end

  # A group can decide what's off-topic in its own space. It cannot decide
  # that illegal content or hate speech is acceptable there, and the instance
  # carries that responsibility regardless of which button the reporter chose
  # — a reporter under stress is not making a legal classification. So these
  # categories are pulled to the instance tier no matter what was requested.
  #
  # `group_id` is kept, so the group still sees it in their queue as context;
  # it's the *ownership* that moves.
  defp force_instance_tier(attrs) do
    category = Map.get(attrs, "category") || Map.get(attrs, :category)

    cond do
      category in Report.always_instance_categories() -> Map.put(attrs, "tier", "instance")
      not group_tier_target_valid?(attrs) -> Map.put(attrs, "tier", "instance")
      true -> attrs
    end
  end

  # `tier` and `group_id` come straight off the request, so without this a
  # client could aim a group-tier report at any group — spamming an unrelated
  # group's moderation queue with content that isn't theirs. A group-tier
  # report has to be about a post that actually lives in that group.
  #
  # Falls back to the instance tier rather than rejecting: the complaint is
  # probably genuine and mis-routed, and dropping it would be worse than
  # sending it to staff.
  defp group_tier_target_valid?(attrs) do
    tier = Map.get(attrs, "tier") || Map.get(attrs, :tier)
    group_id = Map.get(attrs, "group_id") || Map.get(attrs, :group_id)

    if tier != "group" or is_nil(group_id) do
      true
    else
      target_type = Map.get(attrs, "target_type") || Map.get(attrs, :target_type)
      target_id = Map.get(attrs, "target_id") || Map.get(attrs, :target_id)

      target_type == "post" and is_binary(target_id) and
        Repo.exists?(
          from(p in Hybridsocial.Social.Post,
            where:
              p.id == type(^target_id, Ecto.UUID) and p.group_id == type(^group_id, Ecto.UUID)
          )
        )
    end
  end

  @doc """
  How long an untouched group-tier report waits before instance staff can see
  it. DB-backed per the no-hardcoded-limits convention.

  This is the anti-capture mechanism. Without it, a group admin who is
  themselves the subject of a report can simply never action it and instance
  staff never learn it existed — "ignore it" becomes a winning strategy.
  72h balances group autonomy against how long harm continues while a report
  sits; lower it on an instance that wants a tighter leash.
  """
  def group_report_escalation_hours do
    case Hybridsocial.Config.get("group_report_escalation_hours", 72) do
      n when is_integer(n) and n >= 0 -> n
      n when is_binary(n) -> String.to_integer(n)
      _ -> 72
    end
  rescue
    ArgumentError -> 72
  end

  @doc """
  Reports for a group's own moderation queue. Requires moderator-tier rights
  in that group (`Groups.can_moderate?/2`).

  Includes reports forced to the instance tier by category: the group still
  needs to see that something was reported in their space even when the
  instance owns the decision.
  """
  def list_group_reports(group_id, actor_id, opts \\ []) do
    if Hybridsocial.Groups.can_moderate?(group_id, actor_id) do
      reports =
        Report
        |> where([r], r.group_id == ^group_id)
        |> filter_reports_by_status(opts[:status])
        |> order_by([r], desc: r.inserted_at)
        |> paginate(opts)
        |> Repo.all()
        |> Repo.preload([:reporter, :reported])

      {:ok, reports}
    else
      {:error, :forbidden}
    end
  end

  @doc """
  Escalates a group-tier report to the instance tier.

  Allowed for the **reporter** (their complaint, their call if the group isn't
  acting) and for any **group moderator** (handing up something out of their
  depth shouldn't require an accusation). Instance staff don't need this —
  they can already see escalated and aged-out reports.

  Idempotent: escalating an already-instance-tier report is a no-op success.
  """
  def escalate_report(report_id, actor_id) do
    case Repo.get(Report, report_id) do
      nil ->
        {:error, :not_found}

      %Report{tier: "instance"} = report ->
        {:ok, report}

      %Report{} = report ->
        if may_escalate?(report, actor_id) do
          report |> Report.escalate_changeset(actor_id) |> Repo.update()
        else
          {:error, :forbidden}
        end
    end
  end

  defp may_escalate?(%Report{reporter_id: reporter_id}, actor_id) when reporter_id == actor_id,
    do: true

  defp may_escalate?(%Report{group_id: group_id}, actor_id) when is_binary(group_id),
    do: Hybridsocial.Groups.can_moderate?(group_id, actor_id)

  defp may_escalate?(_report, _actor_id), do: false

  @doc """
  Counts of open group-tier reports per group, for instance staff.

  **Metadata only — no contents.** This is what makes a captured queue
  visible without putting every group's internal business in front of
  instance staff. Returns `[%{group_id:, open:, oldest_at:, overdue:}]`.
  """
  def group_report_overview(opts \\ []) do
    cutoff = DateTime.add(DateTime.utc_now(), -group_report_escalation_hours() * 3600, :second)

    Report
    |> where([r], r.tier == "group" and r.status in ["pending", "investigating"])
    |> group_by([r], r.group_id)
    |> select([r], %{
      group_id: r.group_id,
      open: count(r.id),
      oldest_at: min(r.inserted_at),
      overdue: filter(count(r.id), r.inserted_at < ^cutoff)
    })
    |> paginate(opts)
    |> Repo.all()
  end

  defp bump_post_open_report_count(post_id, delta) when is_integer(delta) do
    # GREATEST(..., 0) clamps the count so a stale state (e.g. a
    # backfill that missed a row, or manual SQL surgery in ops) can't
    # drive it negative after a resolve.
    from(p in Hybridsocial.Social.Post,
      where: p.id == ^post_id,
      update: [
        set: [
          open_report_count:
            fragment(
              "GREATEST(COALESCE(?, 0) + ?, 0)",
              p.open_report_count,
              ^delta
            )
        ]
      ]
    )
    |> Repo.update_all([])

    :ok
  end

  @report_preloads [:reporter, :reported, :assigned_moderator]

  # Statuses a moderator still has to act on. `investigating` is what
  # `assign_report/2` moves a report to, so it is as open as `pending`.
  @open_report_statuses ~w(pending investigating)

  def open_report_statuses, do: @open_report_statuses

  def get_report(id) do
    case Repo.get(Report, id) do
      nil -> nil
      report -> Repo.preload(report, @report_preloads)
    end
  end

  def list_reports(opts \\ []) do
    Report
    |> visible_to_instance_staff()
    |> filter_reports_by_status(opts[:status])
    |> order_by([r], desc: r.inserted_at)
    |> paginate(opts)
    |> Repo.all()
    |> Repo.preload(@report_preloads)
  end

  @doc """
  Audit trail for one report (assign / resolve / dismiss), oldest first,
  so the detail view reads as a timeline.
  """
  def report_audit_log(report_id) do
    AuditLog
    |> where([a], a.target_type == "report" and a.target_id == ^report_id)
    |> order_by([a], asc: a.created_at)
    |> limit(100)
    |> Repo.all()
    |> Repo.preload(:actor)
  end

  @doc """
  Other reports filed against the same account, newest first, so a
  moderator can spot a repeat pattern from one report. Excludes `report`.
  """
  def related_reports(%Report{reported_id: reported_id, id: id}, limit \\ 20) do
    Report
    |> where([r], r.reported_id == ^reported_id and r.id != ^id)
    |> order_by([r], desc: r.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Repo.preload(:reporter)
  end

  @doc "Count of still-open reports against an account."
  def open_report_count_for(reported_id) do
    Report
    |> where([r], r.reported_id == ^reported_id and r.status in ^@open_report_statuses)
    |> Repo.aggregate(:count)
  end

  # What instance staff see. Group-tier reports are group business and are
  # excluded by default — otherwise staff drown in other people's squabbles,
  # and group-internal disputes land in front of the instance by default,
  # which members don't expect.
  #
  # Two exceptions, and they're the whole point of the tiering:
  #   * escalated — someone with standing asked for instance eyes
  #   * aged out — open past `group_report_escalation_hours`, so a group that
  #     simply never acts can't bury a complaint
  defp visible_to_instance_staff(query) do
    cutoff = DateTime.add(DateTime.utc_now(), -group_report_escalation_hours() * 3600, :second)

    where(
      query,
      [r],
      r.tier == "instance" or not is_nil(r.escalated_at) or r.inserted_at < ^cutoff
    )
  end

  @doc """
  Hard-deletes resolved + dismissed reports whose `resolved_at` is
  older than `retention_days` days. Pending reports are never pruned
  — they still need moderator action. Returns the number of rows
  removed.
  """
  def prune_closed_reports(retention_days)
      when is_integer(retention_days) and retention_days > 0 do
    cutoff = DateTime.add(DateTime.utc_now(), -retention_days * 86_400, :second)

    {n, _} =
      Report
      |> where([r], r.status in ["resolved", "dismissed"])
      |> where([r], not is_nil(r.resolved_at))
      |> where([r], r.resolved_at < ^cutoff)
      |> Repo.delete_all()

    n
  end

  defp filter_reports_by_status(query, status) when status in [nil, "", "all"], do: query

  defp filter_reports_by_status(query, "open"),
    do: where(query, [r], r.status in ^@open_report_statuses)

  defp filter_reports_by_status(query, status), do: where(query, [r], r.status == ^status)

  def assign_report(report_id, moderator_id) do
    case Repo.get(Report, report_id) do
      nil ->
        {:error, :not_found}

      %Report{status: status} when status not in @open_report_statuses ->
        {:error, :already_closed}

      report ->
        with {:ok, assigned} <- report |> Report.assign_changeset(moderator_id) |> Repo.update() do
          {:ok, Repo.preload(assigned, @report_preloads)}
        end
    end
  end

  def resolve_report(report_id, moderator_id, action_taken) do
    close_report(
      report_id,
      moderator_id,
      &Report.resolve_changeset(&1, action_taken),
      "report.resolved",
      %{action_taken: action_taken}
    )
  end

  def dismiss_report(report_id, moderator_id) do
    close_report(report_id, moderator_id, &Report.dismiss_changeset/1, "report.dismissed", %{})
  end

  # Resolve and dismiss share one path: only an open report can be closed
  # (re-closing would overwrite the original outcome and timestamp), the
  # audit entry is written in the same transaction, and the post's
  # open-report counter drops by one. That counter was incremented when
  # the report was filed, so it has to come down for `investigating`
  # reports too, not only `pending` ones.
  defp close_report(report_id, moderator_id, changeset_fun, action, details) do
    case Repo.get(Report, report_id) do
      nil ->
        {:error, :not_found}

      %Report{status: status} when status not in @open_report_statuses ->
        {:error, :already_closed}

      report ->
        Ecto.Multi.new()
        |> Ecto.Multi.update(:report, changeset_fun.(report))
        |> Ecto.Multi.run(:audit, fn _repo, _changes ->
          log(moderator_id, action, "report", report_id, details)
        end)
        |> Repo.transaction()
        |> case do
          {:ok, %{report: closed}} ->
            if closed.target_type == "post" and is_binary(closed.target_id) do
              bump_post_open_report_count(closed.target_id, -1)
            end

            {:ok, Repo.preload(closed, @report_preloads)}

          {:error, _, changeset, _} ->
            {:error, changeset}
        end
    end
  end

  # ── Audit Log ────────────────────────────────────────────────────────

  def log(actor_id, action, target_type \\ nil, target_id \\ nil, details \\ %{}, ip \\ nil) do
    %AuditLog{}
    |> AuditLog.changeset(%{
      actor_id: actor_id,
      action: action,
      target_type: target_type,
      target_id: target_id,
      details: details,
      ip_address: ip
    })
    |> Repo.insert()
  end

  def list_audit_log(opts \\ []) do
    AuditLog
    |> filter_audit_by_action(opts[:action])
    |> filter_audit_by_actor(opts[:actor_id])
    |> filter_audit_by_date_range(opts[:from], opts[:to])
    |> order_by([a], desc: a.created_at)
    |> paginate(opts)
    |> Repo.all()
    |> Repo.preload(:actor)
  end

  defp filter_audit_by_action(query, nil), do: query
  defp filter_audit_by_action(query, action), do: where(query, [a], a.action == ^action)

  defp filter_audit_by_actor(query, nil), do: query
  defp filter_audit_by_actor(query, actor_id), do: where(query, [a], a.actor_id == ^actor_id)

  defp filter_audit_by_date_range(query, nil, nil), do: query

  defp filter_audit_by_date_range(query, from, nil) do
    where(query, [a], a.created_at >= ^from)
  end

  defp filter_audit_by_date_range(query, nil, to) do
    where(query, [a], a.created_at <= ^to)
  end

  defp filter_audit_by_date_range(query, from, to) do
    where(query, [a], a.created_at >= ^from and a.created_at <= ^to)
  end

  # ── Takedowns (moderation removal + notice + appeal window) ───────────
  #
  # Records that staff removed a piece of content for a reason, notifies the
  # owner (in-app + email) with that reason and the appeal window, and gives
  # the auto-purge worker a `purge_after` deadline. The content itself is
  # soft-deleted by its own context (Groups/Pages/Posts); this only layers the
  # notice + appeal lifecycle on top.

  @default_takedown_days 60

  @doc """
  Creates a takedown record and notifies the content owner. `attrs` needs
  `:target_type`, `:target_id`, `:owner_id`, `:moderator_id`, `:reason`, and
  optional `:category`. `purge_after` is derived from `takedown_retention_days`.
  """
  def create_takedown(attrs) do
    days = takedown_retention_days()

    purge_after =
      DateTime.utc_now()
      |> DateTime.add(days * 86_400, :second)
      |> DateTime.truncate(:microsecond)

    result =
      %Takedown{}
      |> Takedown.changeset(Map.put(attrs, :purge_after, purge_after))
      |> Repo.insert()

    with {:ok, takedown} <- result do
      notify_content_owner(takedown, days)
      {:ok, takedown}
    else
      {:error, changeset} ->
        # Callers (maybe_open_*_takedown) fire-and-forget this, so a rejected
        # takedown — e.g. a reason under the 3-char minimum — would otherwise
        # remove the content while silently sending the owner no notice.
        Logger.warning("Takedown not opened: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  @doc "The appeal window, in days, before an un-appealed takedown is purged."
  def takedown_retention_days do
    case Hybridsocial.Config.get("takedown_retention_days", @default_takedown_days) do
      n when is_integer(n) and n > 0 ->
        n

      s when is_binary(s) ->
        case Integer.parse(s) do
          {n, _} when n > 0 -> n
          _ -> @default_takedown_days
        end

      _ ->
        @default_takedown_days
    end
  end

  # No owner to notify (e.g. an orphaned identity) — nothing to do.
  defp notify_content_owner(%Takedown{owner_id: nil}, _days), do: :ok
  defp notify_content_owner(%Takedown{moderator_id: nil}, _days), do: :ok

  defp notify_content_owner(%Takedown{} = takedown, days) do
    # In-app notification — the bell/SSE "internal message". Actor is the
    # moderator so it isn't self-skipped.
    Hybridsocial.Notifications.create_notification(%{
      recipient_id: takedown.owner_id,
      actor_id: takedown.moderator_id,
      type: "moderation_takedown",
      target_type: notification_target_type(takedown.target_type),
      target_id: takedown.target_id
    })

    # Email is sent directly (the notification email channel is opt-out by
    # default) and fire-and-forget so it never blocks the takedown.
    send_takedown_email(takedown, days)
    :ok
  end

  # media/account_badge aren't linkable notification targets; leave nil.
  defp notification_target_type(t) when t in ~w(group page post), do: t
  defp notification_target_type(_), do: nil

  defp send_takedown_email(%Takedown{owner_id: owner_id} = takedown, days) do
    Task.Supervisor.start_child(Hybridsocial.TaskSupervisor, fn ->
      with identity when not is_nil(identity) <- Hybridsocial.Accounts.get_identity(owner_id),
           user when not is_nil(user) <- Hybridsocial.Accounts.get_user_by_identity(owner_id),
           true <- is_binary(user.email) and user.email != "" do
        identity
        |> Map.from_struct()
        |> Map.put(:email, user.email)
        |> Hybridsocial.Emails.content_removed_email(%{
          target_label: takedown_label(takedown.target_type),
          reason: takedown.reason,
          appeal_days: days
        })
        |> Hybridsocial.Mailer.deliver()
      end
    end)
  end

  defp takedown_label("group"), do: "group"
  defp takedown_label("page"), do: "page"
  defp takedown_label("post"), do: "post"
  defp takedown_label("media"), do: "media"
  defp takedown_label("account_badge"), do: "verification badge"
  defp takedown_label(_), do: "content"

  def get_takedown(id), do: Repo.get(Takedown, id)

  @doc "Takedowns against content owned by `owner_id`, most recent first."
  def list_takedowns_for_owner(owner_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    Takedown
    |> where([t], t.owner_id == ^owner_id)
    |> order_by([t], desc: t.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  # ── Auto-purge (Phase 3): remind, then permanently delete ────────────
  #
  # After the appeal window, an un-appealed takedown is permanently deleted.
  # This is IRREVERSIBLE. `send_purge_reminders/1` warns the owner as the
  # deadline nears; `purge_expired_takedowns/0` does the hard delete. The
  # TakedownPurgeWorker drives both hourly and — importantly — only calls the
  # purge when the `takedown_purge_enabled` setting is on, so the destructive
  # half is opt-in.

  @doc """
  Sends a one-time reminder for each `active` takedown whose purge deadline is
  within `lead_days` and that hasn't been reminded yet. Returns the count sent.
  """
  def send_purge_reminders(lead_days) when is_integer(lead_days) and lead_days >= 0 do
    now = DateTime.utc_now()
    threshold = DateTime.add(now, lead_days * 86_400, :second)

    due =
      Takedown
      |> where([t], t.status == "active")
      |> where([t], is_nil(t.reminded_at))
      |> where([t], t.purge_after <= ^threshold)
      |> Repo.all()

    Enum.each(due, &deliver_purge_reminder/1)
    length(due)
  end

  defp deliver_purge_reminder(%Takedown{} = takedown) do
    days_left =
      DateTime.diff(takedown.purge_after, DateTime.utc_now(), :second)
      |> then(&max(0, div(&1, 86_400)))

    if takedown.owner_id && takedown.moderator_id do
      Hybridsocial.Notifications.create_notification(%{
        recipient_id: takedown.owner_id,
        actor_id: takedown.moderator_id,
        type: "moderation_takedown",
        target_type: notification_target_type(takedown.target_type),
        target_id: takedown.target_id
      })
    end

    send_purge_reminder_email(takedown, days_left)
    takedown |> Ecto.Changeset.change(reminded_at: DateTime.utc_now()) |> Repo.update()
  end

  defp send_purge_reminder_email(%Takedown{owner_id: nil}, _days), do: :ok

  defp send_purge_reminder_email(%Takedown{owner_id: owner_id} = takedown, days_left) do
    Task.Supervisor.start_child(Hybridsocial.TaskSupervisor, fn ->
      with identity when not is_nil(identity) <- Hybridsocial.Accounts.get_identity(owner_id),
           user when not is_nil(user) <- Hybridsocial.Accounts.get_user_by_identity(owner_id),
           true <- is_binary(user.email) and user.email != "" do
        identity
        |> Map.from_struct()
        |> Map.put(:email, user.email)
        |> Hybridsocial.Emails.content_purge_reminder_email(%{
          target_label: takedown_label(takedown.target_type),
          days_left: days_left
        })
        |> Hybridsocial.Mailer.deliver()
      end
    end)
  end

  @doc """
  Permanently deletes the content of every `active` takedown whose window has
  passed, and marks the takedown `purged`. IRREVERSIBLE. Each purge is isolated
  so one failure doesn't halt the batch. Returns the count purged.
  """
  def purge_expired_takedowns do
    now = DateTime.utc_now()

    expired =
      Takedown
      |> where([t], t.status == "active")
      |> where([t], t.purge_after <= ^now)
      |> Repo.all()

    Enum.reduce(expired, 0, fn takedown, acc ->
      if purge_one(takedown), do: acc + 1, else: acc
    end)
  end

  defp purge_one(%Takedown{} = takedown) do
    case purge_takedown_target(takedown) do
      {:ok, _} ->
        takedown |> Takedown.status_changeset("purged") |> Repo.update()

        log(
          takedown.moderator_id,
          "takedown.purged",
          takedown.target_type,
          takedown.target_id,
          %{}
        )

        true

      {:error, reason} ->
        Logger.error("Takedown #{takedown.id} purge failed: #{inspect(reason)}")
        false
    end
  rescue
    e ->
      Logger.error("Takedown #{takedown.id} purge crashed: #{Exception.message(e)}")
      false
  end

  # Hard-delete the removed content. All dependent rows cascade via
  # `on_delete: :delete_all` FKs (members, media, reactions, …). A revoked
  # badge has no content to delete — the revocation just stands for good.
  defp purge_takedown_target(%Takedown{target_type: "group", target_id: id}),
    do: Hybridsocial.Groups.purge_group(id)

  defp purge_takedown_target(%Takedown{target_type: "page", target_id: id}),
    do: Hybridsocial.Pages.purge_page(id)

  defp purge_takedown_target(%Takedown{target_type: "post", target_id: id}),
    do: Hybridsocial.Social.Posts.purge_post(id)

  defp purge_takedown_target(%Takedown{target_type: "account_badge"}), do: {:ok, :no_content}

  defp purge_takedown_target(_), do: {:ok, :no_content}

  @doc """
  Deletes rows that reference `identity_id` through a *non-cascading* foreign key
  so a purge can hard-delete the actor identity without a `foreign_key_violation`.

  A group/page that survives to auto-purge was very likely reported, and
  `reports.reported_id` is `on_delete: :nothing` — deleting the identity would
  otherwise raise and the worker would crash-loop, purging nothing (the exact
  failure the cascade claim overlooked). Reports naming the identity as subject,
  reporter, or assignee are dropped (their subject is being permanently removed);
  `audit_log.actor_id` references are nilified so the immutable log survives.
  Meant to run inside the purge transaction — takes the transaction's `repo`.
  """
  def purge_dangling_identity_refs(repo, identity_id) when is_binary(identity_id) do
    repo.delete_all(
      from(r in "reports",
        where:
          r.reported_id == type(^identity_id, :binary_id) or
            r.reporter_id == type(^identity_id, :binary_id) or
            r.assigned_to == type(^identity_id, :binary_id)
      )
    )

    repo.update_all(
      from(a in "audit_log", where: a.actor_id == type(^identity_id, :binary_id)),
      set: [actor_id: nil]
    )

    {:ok, :cleaned}
  end

  def purge_dangling_identity_refs(_repo, _identity_id), do: {:ok, :no_identity}

  @doc """
  The content owner appeals a takedown. Only the owner may appeal, only while
  the takedown is still `active`, and only once at a time. Filing the appeal
  flips the takedown to `appealed` so the auto-purge worker leaves it alone
  until staff decide.
  """
  def create_takedown_appeal(identity_id, takedown_id, reason) do
    case get_takedown(takedown_id) do
      nil ->
        {:error, :not_found}

      %Takedown{owner_id: owner_id} when owner_id != identity_id ->
        {:error, :forbidden}

      %Takedown{status: status} when status != "active" ->
        {:error, :not_appealable}

      takedown ->
        pending? =
          Appeal
          |> where([a], a.takedown_id == ^takedown_id and a.status == "pending")
          |> Repo.exists?()

        if pending? do
          {:error, :already_pending}
        else
          Ecto.Multi.new()
          |> Ecto.Multi.insert(
            :appeal,
            Appeal.changeset(%Appeal{}, %{
              "identity_id" => identity_id,
              "action_type" => "content_takedown",
              "reason" => reason,
              "takedown_id" => takedown_id
            })
          )
          |> Ecto.Multi.update(:takedown, Takedown.status_changeset(takedown, "appealed"))
          |> Repo.transaction()
          |> case do
            {:ok, %{appeal: appeal}} -> {:ok, appeal}
            {:error, _step, reason, _} -> {:error, reason}
          end
        end
    end
  end

  # Restore the content a takedown removed, dispatching by target type, then
  # mark the takedown `restored`. Called from an already-staff-gated appeal
  # approval, so `admin_id` is a valid instance moderator for the entity-level
  # restore functions (which re-check staff).
  defp restore_takedown_target(%Takedown{} = takedown, admin_id) do
    result =
      case takedown.target_type do
        "group" -> Hybridsocial.Groups.restore_group(takedown.target_id, admin_id)
        "page" -> Hybridsocial.Pages.restore_page(takedown.target_id, admin_id)
        "post" -> Hybridsocial.Social.Posts.admin_restore_post(takedown.target_id, admin_id)
        "account_badge" -> restore_badge(takedown)
        _ -> {:ok, :no_op}
      end

    case result do
      # Only claim the takedown was restored when something actually was — a
      # no-op (unknown/unhandled target) must not be marked "restored".
      {:ok, :no_op} ->
        {:ok, :no_op}

      {:ok, _} ->
        takedown |> Takedown.status_changeset("restored") |> Repo.update()

      error ->
        error
    end
  end

  # Re-grant the verification tier a badge takedown revoked (stored in
  # `category`). Nothing to restore if the tier wasn't recorded.
  defp restore_badge(%Takedown{target_id: identity_id, category: tier})
       when is_binary(tier) and tier != "" do
    case Hybridsocial.Accounts.get_identity(identity_id) do
      nil ->
        {:ok, :no_op}

      identity ->
        Hybridsocial.Accounts.admin_update_identity(identity, %{"verification_tier" => tier})
    end
  end

  defp restore_badge(_), do: {:ok, :no_op}

  @verified_badge_tiers ~w(verified_starter verified_creator verified_pro)

  @doc """
  Opens a takedown notice when staff revoke a verified badge — i.e. a downgrade
  from a verified tier to a non-verified one. A no-op for grants, upgrades, or
  moves between non-verified tiers, and when no reason is given. The revoked-
  from tier is stored in `category` so a later restore can re-grant it.
  """
  def open_badge_takedown(identity_id, admin_id, old_tier, new_tier, reason) do
    if old_tier in @verified_badge_tiers and new_tier not in @verified_badge_tiers and
         is_binary(reason) and reason != "" do
      create_takedown(%{
        target_type: "account_badge",
        target_id: identity_id,
        owner_id: identity_id,
        moderator_id: admin_id,
        reason: reason,
        category: old_tier
      })
    else
      {:ok, :noop}
    end
  end

  # ── Content Filters ──────────────────────────────────────────────────

  def create_filter(attrs) do
    %ContentFilter{}
    |> ContentFilter.changeset(attrs)
    |> Repo.insert()
  end

  def list_filters(opts \\ []) do
    ContentFilter
    |> filter_by_scope(opts[:scope])
    |> order_by([f], desc: f.inserted_at)
    |> Repo.all()
  end

  defp filter_by_scope(query, nil), do: query

  defp filter_by_scope(query, scope) when scope in ["local", "remote"] do
    where(query, [f], f.scope == "all" or f.scope == ^scope)
  end

  defp filter_by_scope(query, _), do: query

  def update_filter(id, attrs) do
    case Repo.get(ContentFilter, id) do
      nil -> {:error, :not_found}
      filter -> filter |> ContentFilter.changeset(attrs) |> Repo.update()
    end
  end

  def delete_filter(id) do
    case Repo.get(ContentFilter, id) do
      nil -> {:error, :not_found}
      filter -> Repo.delete(filter)
    end
  end

  def check_content(text, scope \\ "all") do
    Hybridsocial.Moderation.FilterResolver.impl().check(text, %{context: "posts", scope: scope})
  end

  @doc """
  Checks content and automatically queues for review if flagged.
  Returns the filter result unchanged; queuing is a side-effect.
  """
  def check_content_and_queue(text, item_type, item_id, scope \\ "all") do
    result = check_content(text, scope)

    case result do
      {:flag, reason} ->
        queue_for_review(%{
          "item_type" => item_type,
          "item_id" => item_id,
          "source" => "content_filter",
          "reason" => reason,
          "severity" => "medium"
        })

        result

      _ ->
        result
    end
  end

  # ── Banned Domains ───────────────────────────────────────────────────

  def ban_domain(domain, type, reason, admin_id) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:banned_domain, fn _ ->
      %BannedDomain{}
      |> BannedDomain.changeset(%{
        domain: domain,
        type: type,
        reason: reason,
        created_by: admin_id
      })
    end)
    |> Ecto.Multi.run(:audit, fn _repo, _changes ->
      log(admin_id, "domain.banned", "domain", nil, %{domain: domain, type: type, reason: reason})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{banned_domain: banned_domain}} -> {:ok, banned_domain}
      {:error, _, changeset, _} -> {:error, changeset}
    end
  end

  def unban_domain(domain, admin_id) do
    case Repo.get(BannedDomain, String.downcase(domain)) do
      nil ->
        {:error, :not_found}

      banned_domain ->
        Ecto.Multi.new()
        |> Ecto.Multi.delete(:banned_domain, banned_domain)
        |> Ecto.Multi.run(:audit, fn _repo, _changes ->
          log(admin_id, "domain.unbanned", "domain", nil, %{domain: domain})
        end)
        |> Repo.transaction()
        |> case do
          {:ok, _} -> :ok
          {:error, _, reason, _} -> {:error, reason}
        end
    end
  end

  def list_banned_domains do
    BannedDomain
    |> order_by([d], asc: d.domain)
    |> Repo.all()
  end

  def domain_banned?(domain, type) do
    domain = String.downcase(domain)

    BannedDomain
    |> where([d], d.domain == ^domain)
    |> where([d], d.type == ^type or d.type == "both")
    |> Repo.exists?()
  end

  # ── IP Bans ────────────────────────────────────────────────────────────

  def list_ip_bans do
    IpBan
    |> order_by([b], desc: b.inserted_at)
    |> Repo.all()
  end

  def create_ip_ban(attrs) do
    %IpBan{}
    |> IpBan.changeset(attrs)
    |> Repo.insert()
  end

  def delete_ip_ban(id) do
    case Repo.get(IpBan, id) do
      nil -> {:error, :not_found}
      ip_ban -> Repo.delete(ip_ban)
    end
  end

  @doc """
  Checks if an IP address matches any active (non-expired) ban, including CIDR ranges.
  """
  def ip_banned?(ip_string) when is_binary(ip_string) do
    now = DateTime.utc_now()

    IpBan
    |> where([b], is_nil(b.expires_at) or b.expires_at > ^now)
    |> Repo.all()
    |> Enum.any?(fn ban -> ip_matches_ban?(ip_string, ban) end)
  end

  defp ip_matches_ban?(ip_string, %IpBan{ip_address: ban_ip, subnet_mask: nil}) do
    ip_string == ban_ip
  end

  defp ip_matches_ban?(ip_string, %IpBan{ip_address: ban_ip, subnet_mask: mask}) do
    with {:ok, client_addr} <- :inet.parse_address(to_charlist(ip_string)),
         {:ok, ban_addr} <- :inet.parse_address(to_charlist(ban_ip)),
         {prefix_len, ""} <- Integer.parse(mask) do
      ip_in_cidr?(client_addr, ban_addr, prefix_len)
    else
      _ -> false
    end
  end

  defp ip_in_cidr?(client, network, prefix_len) do
    client_bits = ip_to_bits(client)
    network_bits = ip_to_bits(network)

    if byte_size(client_bits) == byte_size(network_bits) do
      <<client_prefix::bitstring-size(prefix_len), _::bitstring>> = client_bits
      <<network_prefix::bitstring-size(prefix_len), _::bitstring>> = network_bits
      client_prefix == network_prefix
    else
      false
    end
  end

  defp ip_to_bits({a, b, c, d}) do
    <<a::8, b::8, c::8, d::8>>
  end

  defp ip_to_bits({a, b, c, d, e, f, g, h}) do
    <<a::16, b::16, c::16, d::16, e::16, f::16, g::16, h::16>>
  end

  # ── Email Domain Bans ─────────────────────────────────────────────────

  def list_email_domain_bans do
    EmailDomainBan
    |> order_by([b], asc: b.domain)
    |> Repo.all()
  end

  def create_email_domain_ban(attrs) do
    %EmailDomainBan{}
    |> EmailDomainBan.changeset(attrs)
    |> Repo.insert()
  end

  def delete_email_domain_ban(id) do
    case Repo.get(EmailDomainBan, id) do
      nil -> {:error, :not_found}
      ban -> Repo.delete(ban)
    end
  end

  def email_domain_banned?(domain) when is_binary(domain) do
    domain = String.downcase(domain)

    EmailDomainBan
    |> where([b], b.domain == ^domain)
    |> Repo.exists?()
  end

  # ── Webhooks ─────────────────────────────────────────────────────────

  def create_webhook(attrs) do
    %Webhook{}
    |> Webhook.changeset(attrs)
    |> Repo.insert()
  end

  def list_webhooks do
    Webhook
    |> order_by([w], desc: w.inserted_at)
    |> Repo.all()
  end

  def update_webhook(id, attrs) do
    case Repo.get(Webhook, id) do
      nil -> {:error, :not_found}
      webhook -> webhook |> Webhook.changeset(attrs) |> Repo.update()
    end
  end

  def delete_webhook(id) do
    case Repo.get(Webhook, id) do
      nil -> {:error, :not_found}
      webhook -> Repo.delete(webhook)
    end
  end

  @doc """
  Known webhook events. Kept as a static catalog so the admin UI can
  render checkboxes instead of forcing admins to hand-type event
  strings, and so callers get a compile-time crash on typos via
  `Enum.member?/2` in tests.
  """
  def known_events do
    [
      "post.created",
      "post.deleted",
      "user.registered",
      "user.suspended",
      "user.unsuspended",
      "report.filed",
      "report.resolved",
      "appeal.filed",
      "moderation.queued",
      "federation.instance_blocked"
    ]
  end

  @doc """
  Enqueues a webhook delivery for every enabled webhook that subscribes
  to `event`. An empty `events` array on a webhook means "all events".
  The `WebhookDeliveryWorker` drains the queue and retries with
  exponential backoff on non-2xx so a flapping receiver doesn't
  silently lose events.
  """
  def fire_webhook(event, payload) when is_binary(event) do
    now = DateTime.utc_now()

    Webhook
    |> where([w], w.enabled == true)
    |> Repo.all()
    |> Enum.filter(fn w -> w.events == [] or event in w.events end)
    |> Enum.each(fn webhook ->
      %WebhookDelivery{}
      |> WebhookDelivery.changeset(%{
        webhook_id: webhook.id,
        event: event,
        payload: payload,
        status: "pending",
        attempts: 0,
        next_attempt_at: now
      })
      |> Repo.insert()
    end)

    :ok
  end

  def list_recent_deliveries(webhook_id, limit \\ 20) do
    WebhookDelivery
    |> where([d], d.webhook_id == ^webhook_id)
    |> order_by([d], desc: d.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  # ── Appeals ──────────────────────────────────────────────────────────

  def create_appeal(attrs) do
    identity_id = attrs["identity_id"] || attrs[:identity_id]
    action_type = attrs["action_type"] || attrs[:action_type]

    # Enforce: one pending appeal per action_type per user
    existing =
      Appeal
      |> where([a], a.identity_id == ^identity_id)
      |> where([a], a.action_type == ^action_type)
      |> where([a], a.status == "pending")
      |> Repo.exists?()

    if existing do
      {:error, :already_pending}
    else
      %Appeal{}
      |> Appeal.changeset(attrs)
      |> Repo.insert()
    end
  end

  def get_appeal(id) do
    case Repo.get(Appeal, id) do
      nil -> nil
      appeal -> Repo.preload(appeal, [:identity, :reviewer])
    end
  end

  def list_appeals(opts \\ []) do
    Appeal
    |> filter_appeals_by_status(opts[:status])
    |> filter_appeals_by_identity(opts[:identity_id])
    |> order_by([a], desc: a.inserted_at)
    |> paginate(opts)
    |> Repo.all()
    |> Repo.preload([:identity, :reviewer])
  end

  defp filter_appeals_by_status(query, nil), do: query
  defp filter_appeals_by_status(query, status), do: where(query, [a], a.status == ^status)

  defp filter_appeals_by_identity(query, nil), do: query
  defp filter_appeals_by_identity(query, id), do: where(query, [a], a.identity_id == ^id)

  @doc """
  Hard-deletes approved + rejected appeals whose `reviewed_at` is
  older than `retention_days` days. Pending appeals are never
  pruned — they still need admin action. Returns the row count.
  """
  def prune_closed_appeals(retention_days)
      when is_integer(retention_days) and retention_days > 0 do
    cutoff = DateTime.add(DateTime.utc_now(), -retention_days * 86_400, :second)

    {n, _} =
      Appeal
      |> where([a], a.status in ["approved", "rejected"])
      |> where([a], not is_nil(a.reviewed_at))
      |> where([a], a.reviewed_at < ^cutoff)
      |> Repo.delete_all()

    n
  end

  def approve_appeal(appeal_id, admin_id, response \\ nil) do
    case get_appeal(appeal_id) do
      nil ->
        {:error, :not_found}

      %{status: status} when status != "pending" ->
        {:error, :already_reviewed}

      appeal ->
        Ecto.Multi.new()
        |> Ecto.Multi.update(
          :appeal,
          Appeal.review_changeset(appeal, %{
            status: "approved",
            reviewed_by: admin_id,
            reviewed_at: DateTime.utc_now(),
            response: response
          })
        )
        |> Ecto.Multi.run(:reverse_action, fn _repo, %{appeal: approved_appeal} ->
          reverse_moderation_action(approved_appeal, admin_id)
        end)
        |> Ecto.Multi.run(:audit, fn _repo, %{appeal: approved_appeal} ->
          log(admin_id, "appeal.approved", "appeal", approved_appeal.id, %{
            action_type: approved_appeal.action_type,
            identity_id: approved_appeal.identity_id
          })
        end)
        |> Repo.transaction()
        |> case do
          {:ok, %{appeal: appeal}} -> {:ok, Repo.preload(appeal, [:identity, :reviewer])}
          {:error, _, reason, _} -> {:error, reason}
        end
    end
  end

  def reject_appeal(appeal_id, admin_id, response \\ nil) do
    case get_appeal(appeal_id) do
      nil ->
        {:error, :not_found}

      %{status: status} when status != "pending" ->
        {:error, :already_reviewed}

      appeal ->
        Ecto.Multi.new()
        |> Ecto.Multi.update(
          :appeal,
          Appeal.review_changeset(appeal, %{
            status: "rejected",
            reviewed_by: admin_id,
            reviewed_at: DateTime.utc_now(),
            response: response
          })
        )
        |> Ecto.Multi.run(:reactivate_takedown, fn _repo, %{appeal: rejected_appeal} ->
          reactivate_takedown_on_reject(rejected_appeal)
        end)
        |> Ecto.Multi.run(:audit, fn _repo, %{appeal: rejected_appeal} ->
          log(admin_id, "appeal.rejected", "appeal", rejected_appeal.id, %{
            action_type: rejected_appeal.action_type,
            identity_id: rejected_appeal.identity_id
          })
        end)
        |> Repo.transaction()
        |> case do
          {:ok, %{appeal: appeal}} -> {:ok, Repo.preload(appeal, [:identity, :reviewer])}
          {:error, _, reason, _} -> {:error, reason}
        end
    end
  end

  # Appeal rejected: the takedown stands, so flip it from `appealed` back to
  # `active` — the auto-purge window resumes. Non-takedown appeals are a no-op.
  defp reactivate_takedown_on_reject(%Appeal{takedown_id: nil}), do: {:ok, :no_op}

  defp reactivate_takedown_on_reject(%Appeal{takedown_id: takedown_id}) do
    case get_takedown(takedown_id) do
      nil ->
        {:ok, :no_op}

      %Takedown{status: "appealed"} = td ->
        td |> Takedown.status_changeset("active") |> Repo.update()

      _ ->
        {:ok, :no_op}
    end
  end

  # A content-takedown appeal: restore the specific group/page/post.
  defp reverse_moderation_action(%Appeal{takedown_id: takedown_id}, admin_id)
       when not is_nil(takedown_id) do
    case get_takedown(takedown_id) do
      nil -> {:ok, :no_op}
      takedown -> restore_takedown_target(takedown, admin_id)
    end
  end

  defp reverse_moderation_action(
         %Appeal{action_type: "suspension", identity_id: identity_id},
         _admin_id
       ) do
    case Repo.get(Identity, identity_id) do
      nil -> {:ok, :no_op}
      identity -> Hybridsocial.Accounts.unsuspend_identity(identity)
    end
  end

  defp reverse_moderation_action(
         %Appeal{action_type: "silencing", identity_id: identity_id},
         _admin_id
       ) do
    case Repo.get(Identity, identity_id) do
      nil ->
        {:ok, :no_op}

      identity ->
        identity
        |> Ecto.Changeset.change(is_silenced: false)
        |> Repo.update()
    end
  end

  defp reverse_moderation_action(
         %Appeal{action_type: "shadow_ban", identity_id: identity_id},
         _admin_id
       ) do
    case Repo.get(Identity, identity_id) do
      nil ->
        {:ok, :no_op}

      identity ->
        identity
        |> Ecto.Changeset.change(is_shadow_banned: false)
        |> Repo.update()
    end
  end

  # For a bare post_removal/warning (no linked takedown), there's no automatic
  # reversal — the moderator restores manually.
  defp reverse_moderation_action(_appeal, _admin_id), do: {:ok, :no_op}

  # ── Moderation Notes ────────────────────────────────────────────────

  def create_moderation_note(attrs) do
    %ModerationNote{}
    |> ModerationNote.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, note} -> {:ok, Repo.preload(note, [:author, :target_identity])}
      error -> error
    end
  end

  def list_moderation_notes(target_identity_id) do
    ModerationNote
    |> where([n], n.target_identity_id == ^target_identity_id)
    |> order_by([n], desc: n.inserted_at)
    |> Repo.all()
    |> Repo.preload([:author, :target_identity])
  end

  def delete_moderation_note(id) do
    case Repo.get(ModerationNote, id) do
      nil -> {:error, :not_found}
      note -> Repo.delete(note)
    end
  end

  # ── Moderation Queue ──────────────────────────────────────────────────

  @doc """
  Adds an item to the moderation review queue.
  Attrs should include: item_type, item_id, source, reason, and optionally severity.
  """
  def queue_for_review(attrs) do
    result =
      %QueuedItem{}
      |> QueuedItem.changeset(attrs)
      |> Repo.insert()

    with {:ok, item} <- result do
      # 1) Realtime push to every open admin panel via SSE.
      Phoenix.PubSub.broadcast(
        Hybridsocial.PubSub,
        "moderation",
        %{
          event: "queued",
          payload: %{
            id: item.id,
            item_type: item.item_type,
            item_id: item.item_id,
            source: item.source,
            reason: item.reason,
            severity: item.severity,
            status: item.status,
            inserted_at: item.inserted_at
          }
        }
      )

      # 2) Fire-and-forget email notify (throttled per staff member).
      Task.Supervisor.start_child(Hybridsocial.TaskSupervisor, fn ->
        notify_staff_by_email(item)
      end)

      # 3) External integrations (Slack/Matrix/on-call pager etc.)
      fire_webhook("moderation.queued", %{
        id: item.id,
        item_type: item.item_type,
        item_id: item.item_id,
        source: item.source,
        reason: item.reason,
        severity: item.severity
      })
    end

    result
  end

  @doc """
  Emails every staff member who has opted in to the
  `moderation_queue` notification preference. Throttled to at most
  one email per recipient per throttle window (default 10 min)
  via a Valkey key so a filter-rule mistake that flags 500 items
  in a minute doesn't produce 500 inboxes of 500 emails.
  """
  def notify_staff_by_email(%QueuedItem{} = item) do
    require Logger
    alias Hybridsocial.{Accounts.Identity, Accounts.User, Auth.RBAC, Notifications, Cache}

    throttle_sec =
      case Hybridsocial.Config.get("moderation_email_throttle_seconds", 600) do
        n when is_integer(n) and n > 0 -> n
        _ -> 600
      end

    staff_ids =
      from(r in Hybridsocial.Auth.IdentityRole,
        distinct: true,
        select: r.identity_id,
        where: is_nil(r.expires_at) or r.expires_at > ^DateTime.utc_now()
      )
      |> Repo.all()

    for identity_id <- staff_ids do
      if Notifications.should_notify?(identity_id, "moderation_queue", :email) and
           RBAC.staff?(identity_id) do
        throttle_key = "mod_email:#{identity_id}"

        case Cache.get(throttle_key) do
          nil ->
            # Set the throttle flag BEFORE dispatching to avoid a
            # race where two near-simultaneous inserts both race past
            # the check.
            Cache.set(throttle_key, "1", throttle_sec)

            with %Identity{} = identity <- Repo.get(Identity, identity_id),
                 %User{email: email} when is_binary(email) and email != "" <-
                   Repo.get_by(User, identity_id: identity_id) do
              try do
                Hybridsocial.Emails.moderation_queue_email(email, identity, item)
                |> Hybridsocial.Mailer.deliver()
              rescue
                e ->
                  Logger.warning(
                    "moderation email failed for #{identity_id}: #{Exception.message(e)}"
                  )
              end
            end

          _ ->
            :ok
        end
      end
    end
  end

  @doc """
  Lists moderation queue items with optional filters for status, item_type, and severity.
  """
  def list_queue(opts \\ []) do
    QueuedItem
    |> filter_queue_by_status(opts[:status])
    |> filter_queue_by_item_type(opts[:item_type])
    |> filter_queue_by_severity(opts[:severity])
    |> order_by([q], desc: q.inserted_at)
    |> paginate(opts)
    |> Repo.all()
  end

  defp filter_queue_by_status(query, nil), do: query
  defp filter_queue_by_status(query, status), do: where(query, [q], q.status == ^status)

  defp filter_queue_by_item_type(query, nil), do: query
  defp filter_queue_by_item_type(query, type), do: where(query, [q], q.item_type == ^type)

  defp filter_queue_by_severity(query, nil), do: query
  defp filter_queue_by_severity(query, severity), do: where(query, [q], q.severity == ^severity)

  @doc """
  Retrieves a single queued item by ID.
  """
  def get_queued_item(id) do
    Repo.get(QueuedItem, id)
  end

  @doc """
  Approves a queued item (content stays visible).
  """
  def approve_queued_item(item_id, reviewer_id) do
    case Repo.get(QueuedItem, item_id) do
      nil ->
        {:error, :not_found}

      %QueuedItem{status: "pending"} = item ->
        item
        |> QueuedItem.approve_changeset(reviewer_id)
        |> Repo.update()

      %QueuedItem{status: "escalated"} = item ->
        item
        |> QueuedItem.approve_changeset(reviewer_id)
        |> Repo.update()

      _item ->
        {:error, :already_reviewed}
    end
  end

  @doc """
  Rejects a queued item (content is deleted/hidden).
  For posts, performs a soft delete. For accounts, suspends.
  """
  def reject_queued_item(item_id, reviewer_id, reason \\ "") do
    case Repo.get(QueuedItem, item_id) do
      nil ->
        {:error, :not_found}

      %QueuedItem{status: status} = item when status in ["pending", "escalated"] ->
        Ecto.Multi.new()
        |> Ecto.Multi.update(:item, QueuedItem.reject_changeset(item, reviewer_id))
        |> Ecto.Multi.run(:enforce, fn _repo, _changes ->
          enforce_queue_rejection(item, reviewer_id, reason)
        end)
        |> Repo.transaction()
        |> case do
          {:ok, %{item: item}} -> {:ok, item}
          {:error, _, reason, _} -> {:error, reason}
        end

      _item ->
        {:error, :already_reviewed}
    end
  end

  defp enforce_queue_rejection(%QueuedItem{item_type: "post", item_id: post_id}, admin_id, reason) do
    Hybridsocial.Social.Posts.admin_delete_post(post_id, admin_id, reason)
  end

  defp enforce_queue_rejection(
         %QueuedItem{item_type: "account", item_id: identity_id},
         admin_id,
         _reason
       ) do
    case Repo.get(Identity, identity_id) do
      nil ->
        {:ok, :no_op}

      identity ->
        case Hybridsocial.Accounts.suspend_identity(identity) do
          {:ok, updated} ->
            log(admin_id, "account.suspended", "identity", identity_id, %{
              source: "moderation_queue"
            })

            {:ok, updated}

          error ->
            error
        end
    end
  end

  defp enforce_queue_rejection(_item, _admin_id, _reason), do: {:ok, :no_op}

  @doc """
  Escalates a queued item to a higher-level moderator.
  """
  def escalate_queued_item(item_id, admin_id) do
    case Repo.get(QueuedItem, item_id) do
      nil ->
        {:error, :not_found}

      %QueuedItem{status: "pending"} = item ->
        case item |> QueuedItem.escalate_changeset() |> Repo.update() do
          {:ok, updated} ->
            log(admin_id, "queue_item.escalated", "queued_item", item_id, %{
              item_type: item.item_type,
              item_id: item.item_id
            })

            {:ok, updated}

          error ->
            error
        end

      _item ->
        {:error, :cannot_escalate}
    end
  end

  @doc """
  Returns counts of queued items grouped by status for the dashboard.
  """
  def queue_stats do
    QueuedItem
    |> group_by([q], q.status)
    |> select([q], {q.status, count(q.id)})
    |> Repo.all()
    |> Map.new()
  end

  # ── Media Hash Bans ─────────────────────────────────────────────────

  @doc "Lists all media hash bans, ordered by most recent first."
  def list_media_hash_bans do
    MediaHashBan
    |> order_by([b], desc: b.inserted_at)
    |> Repo.all()
  end

  @doc "Creates a media hash ban."
  def create_media_hash_ban(attrs) do
    %MediaHashBan{}
    |> MediaHashBan.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Deletes a media hash ban by ID."
  def delete_media_hash_ban(id) do
    case Repo.get(MediaHashBan, id) do
      nil -> {:error, :not_found}
      ban -> Repo.delete(ban)
    end
  end

  @doc "Returns true if the given hash is in the ban list (SHA256 match)."
  def media_hash_banned?(hash) when is_binary(hash) do
    hash = String.downcase(hash)

    MediaHashBan
    |> where([b], b.hash == ^hash)
    |> Repo.exists?()
  end

  # ── Hashtag Blocks ───────────────────────────────────────────────────

  @doc "Lists all hashtag blocks, most recent first."
  def list_blocked_hashtags do
    BlockedHashtag
    |> order_by([b], desc: b.inserted_at)
    |> Repo.all()
  end

  @doc "Blocks a hashtag, or updates the existing block on it."
  def block_hashtag(attrs) do
    result =
      %BlockedHashtag{}
      |> BlockedHashtag.changeset(attrs)
      |> Repo.insert(
        on_conflict: {:replace, [:action, :reason, :created_by, :updated_at]},
        conflict_target: :name,
        returning: true
      )

    with {:ok, _} <- result, do: flush_feed_caches()
    result
  end

  @doc "Removes a hashtag block by ID."
  def unblock_hashtag(id) do
    case Repo.get(BlockedHashtag, id) do
      nil ->
        {:error, :not_found}

      block ->
        result = Repo.delete(block)
        flush_feed_caches()
        result
    end
  end

  @doc "A query of the tag names whose posts are hidden from public surfaces."
  def hidden_hashtag_names do
    hiding_actions = BlockedHashtag.hiding_actions()

    BlockedHashtag
    |> where([b], b.action in ^hiding_actions)
    |> select([b], b.name)
  end

  @doc "Returns true if posts carrying this tag are hidden from public surfaces."
  def hashtag_hidden?(name) when is_binary(name) do
    normalized = BlockedHashtag.normalize_name(name)

    hidden_hashtag_names()
    |> where([b], b.name == ^normalized)
    |> Repo.exists?()
  end

  @doc "Returns true if any of these tags is hidden from public surfaces."
  def any_hashtag_hidden?([]), do: false

  def any_hashtag_hidden?(names) when is_list(names) do
    normalized = Enum.map(names, &BlockedHashtag.normalize_name/1)

    hidden_hashtag_names()
    |> where([b], b.name in ^normalized)
    |> Repo.exists?()
  end

  @doc "Returns the first of these tags blocked with `reject`, or nil."
  def rejected_hashtag_among([]), do: nil

  def rejected_hashtag_among(names) when is_list(names) do
    BlockedHashtag
    |> where([b], b.action == "reject" and b.name in ^names)
    |> select([b], b.name)
    |> limit(1)
    |> Repo.one()
  end

  # Timelines and tag pages are served from snapshots, so without this a block
  # would take up to a few minutes to reach them. Admin blocks are rare, and the
  # next read or prewarm cycle refills the cache. Best-effort: an unavailable
  # cache must not fail the block, and the snapshots expire on their own anyway.
  defp flush_feed_caches do
    Hybridsocial.Cache.flush_pattern("feed:*")
    :ok
  rescue
    e ->
      Logger.warning("Failed to flush feed caches: #{inspect(e)}")
      :ok
  end

  # ── Pagination Helper ────────────────────────────────────────────────

  defp paginate(query, opts) do
    limit = opts[:limit] || 20
    offset = opts[:offset] || 0

    query
    |> limit(^limit)
    |> offset(^offset)
  end
end
