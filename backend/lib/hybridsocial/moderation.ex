defmodule Hybridsocial.Moderation do
  @moduledoc """
  The Moderation context. Manages reports, audit log, content filters,
  banned domains, and moderation webhooks.
  """
  import Ecto.Query
  alias Hybridsocial.Repo
  alias Hybridsocial.Moderation.{Report, AuditLog, ContentFilter, BannedDomain, Webhook}

  # ── Reports ──────────────────────────────────────────────────────────

  def create_report(reporter_id, attrs) do
    %Report{}
    |> Report.changeset(Map.put(attrs, "reporter_id", reporter_id))
    |> Repo.insert()
  end

  def get_report(id) do
    case Repo.get(Report, id) do
      nil -> nil
      report -> Repo.preload(report, [:reporter, :reported])
    end
  end

  def list_reports(opts \\ []) do
    Report
    |> filter_reports_by_status(opts[:status])
    |> order_by([r], desc: r.inserted_at)
    |> paginate(opts)
    |> Repo.all()
    |> Repo.preload([:reporter, :reported])
  end

  defp filter_reports_by_status(query, nil), do: query
  defp filter_reports_by_status(query, status), do: where(query, [r], r.status == ^status)

  def assign_report(report_id, moderator_id) do
    case Repo.get(Report, report_id) do
      nil ->
        {:error, :not_found}

      report ->
        report
        |> Report.assign_changeset(moderator_id)
        |> Repo.update()
    end
  end

  def resolve_report(report_id, moderator_id, action_taken) do
    case Repo.get(Report, report_id) do
      nil ->
        {:error, :not_found}

      report ->
        Ecto.Multi.new()
        |> Ecto.Multi.update(:report, Report.resolve_changeset(report, action_taken))
        |> Ecto.Multi.run(:audit, fn _repo, _changes ->
          log(moderator_id, "report.resolved", "report", report_id, %{action_taken: action_taken})
        end)
        |> Repo.transaction()
        |> case do
          {:ok, %{report: report}} -> {:ok, report}
          {:error, _, changeset, _} -> {:error, changeset}
        end
    end
  end

  def dismiss_report(report_id, moderator_id) do
    case Repo.get(Report, report_id) do
      nil ->
        {:error, :not_found}

      report ->
        Ecto.Multi.new()
        |> Ecto.Multi.update(:report, Report.dismiss_changeset(report))
        |> Ecto.Multi.run(:audit, fn _repo, _changes ->
          log(moderator_id, "report.dismissed", "report", report_id, %{})
        end)
        |> Repo.transaction()
        |> case do
          {:ok, %{report: report}} -> {:ok, report}
          {:error, _, changeset, _} -> {:error, changeset}
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

  # ── Content Filters ──────────────────────────────────────────────────

  def create_filter(attrs) do
    %ContentFilter{}
    |> ContentFilter.changeset(attrs)
    |> Repo.insert()
  end

  def list_filters do
    ContentFilter
    |> order_by([f], desc: f.inserted_at)
    |> Repo.all()
  end

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

  def check_content(text) do
    filters = list_filters()
    do_check_content(text, filters)
  end

  defp do_check_content(text, []), do: {:ok, text}

  defp do_check_content(text, [filter | rest]) do
    case apply_filter(text, filter) do
      {:reject, reason} ->
        {:reject, reason}

      {:flag, reason} ->
        {:flag, reason}

      {:replace, new_text} ->
        do_check_content(new_text, rest)

      :ok ->
        do_check_content(text, rest)
    end
  end

  defp apply_filter(text, %ContentFilter{type: "word", pattern: pattern, action: action} = filter) do
    regex = ~r/\b#{Regex.escape(pattern)}\b/i

    if Regex.match?(regex, text) do
      handle_filter_match(text, regex, action, filter)
    else
      :ok
    end
  end

  defp apply_filter(text, %ContentFilter{type: "phrase", pattern: pattern, action: action} = filter) do
    regex = ~r/#{Regex.escape(pattern)}/i

    if Regex.match?(regex, text) do
      handle_filter_match(text, regex, action, filter)
    else
      :ok
    end
  end

  defp apply_filter(text, %ContentFilter{type: "regex", pattern: pattern, action: action} = filter) do
    case Regex.compile(pattern, "i") do
      {:ok, regex} ->
        if Regex.match?(regex, text) do
          handle_filter_match(text, regex, action, filter)
        else
          :ok
        end

      {:error, _} ->
        :ok
    end
  end

  defp handle_filter_match(_text, _regex, "reject", filter) do
    {:reject, "Content matched filter: #{filter.pattern}"}
  end

  defp handle_filter_match(_text, _regex, "flag", filter) do
    {:flag, "Content matched filter: #{filter.pattern}"}
  end

  defp handle_filter_match(text, regex, "replace", filter) do
    new_text = Regex.replace(regex, text, filter.replacement || "")
    {:replace, new_text}
  end

  # ── Banned Domains ───────────────────────────────────────────────────

  def ban_domain(domain, type, reason, admin_id) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:banned_domain, fn _ ->
      %BannedDomain{}
      |> BannedDomain.changeset(%{domain: domain, type: type, reason: reason, created_by: admin_id})
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

  def fire_webhook(event, payload) do
    Webhook
    |> where([w], w.enabled == true)
    |> Repo.all()
    |> Enum.filter(fn w -> event in w.events || w.events == [] end)
    |> Enum.each(fn webhook ->
      Task.start(fn -> deliver_webhook(webhook, event, payload) end)
    end)

    :ok
  end

  defp deliver_webhook(webhook, event, payload) do
    body = Jason.encode!(%{event: event, payload: payload})

    headers = [
      {"content-type", "application/json"},
      {"x-webhook-event", event}
    ]

    headers =
      if webhook.secret do
        signature = :crypto.mac(:hmac, :sha256, webhook.secret, body) |> Base.encode16(case: :lower)
        [{"x-webhook-signature", signature} | headers]
      else
        headers
      end

    HTTPoison.post(webhook.url, body, headers)
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
