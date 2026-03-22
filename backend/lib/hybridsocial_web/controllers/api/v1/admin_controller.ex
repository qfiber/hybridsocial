defmodule HybridsocialWeb.Api.V1.AdminController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Moderation
  alias Hybridsocial.Accounts
  alias Hybridsocial.Auth.RBAC
  import HybridsocialWeb.Helpers.Pagination, only: [clamp_limit: 1]

  # ── Permission helper ──────────────────────────────────────────────

  defp require_permission(conn, permission) do
    identity = conn.assigns.current_identity

    if RBAC.has_permission?(identity.id, permission) do
      :ok
    else
      {:error, permission}
    end
  end

  defp deny(conn, permission) do
    conn
    |> put_status(:forbidden)
    |> json(%{error: "permission.denied", required: permission})
  end

  # ── Reports ──────────────────────────────────────────────────────────

  def list_reports(conn, params) do
    with :ok <- require_permission(conn, "reports.view") do
      opts = [
        status: params["status"],
        limit: clamp_limit(params["limit"]),
        offset: parse_int(params["offset"], 0)
      ]

      reports = Moderation.list_reports(opts)

      conn
      |> put_status(:ok)
      |> json(%{data: Enum.map(reports, &serialize_report/1)})
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def show_report(conn, %{"id" => id}) do
    with :ok <- require_permission(conn, "reports.view") do
      case Moderation.get_report(id) do
        nil ->
          conn |> put_status(:not_found) |> json(%{error: "report.not_found"})

        report ->
          conn |> put_status(:ok) |> json(%{data: serialize_report(report)})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def resolve_report(conn, %{"id" => id} = params) do
    with :ok <- require_permission(conn, "reports.manage") do
      moderator_id = conn.assigns.current_identity.id
      action_taken = params["action_taken"] || "resolved"

      case Moderation.resolve_report(id, moderator_id, action_taken) do
        {:ok, report} ->
          conn |> put_status(:ok) |> json(%{data: serialize_report(report)})

        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "report.not_found"})

        {:error, _} ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: "report.resolve_failed"})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def assign_report(conn, %{"id" => id} = params) do
    with :ok <- require_permission(conn, "reports.assign") do
      moderator_id = params["moderator_id"] || conn.assigns.current_identity.id

      case Moderation.assign_report(id, moderator_id) do
        {:ok, report} ->
          conn |> put_status(:ok) |> json(%{data: serialize_report(report)})

        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "report.not_found"})

        {:error, _} ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: "report.assign_failed"})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  # ── Audit Log ────────────────────────────────────────────────────────

  def audit_log(conn, params) do
    with :ok <- require_permission(conn, "audit_log.view") do
      opts = [
        action: params["action"],
        actor_id: params["actor_id"],
        limit: clamp_limit(params["limit"]),
        offset: parse_int(params["offset"], 0)
      ]

      entries = Moderation.list_audit_log(opts)

      conn
      |> put_status(:ok)
      |> json(%{data: Enum.map(entries, &serialize_audit_entry/1)})
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  # ── Accounts ─────────────────────────────────────────────────────────

  def list_accounts(conn, _params) do
    with :ok <- require_permission(conn, "users.view") do
      accounts = Accounts.list_identities()

      conn
      |> put_status(:ok)
      |> json(%{data: Enum.map(accounts, &serialize_account/1)})
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def account_action(conn, %{"id" => id, "action" => action} = params) do
    required =
      case action do
        "suspend" -> "users.suspend"
        "unsuspend" -> "users.suspend"
        "warn" -> "users.warn"
        _ -> "users.view"
      end

    with :ok <- require_permission(conn, required) do
      admin_id = conn.assigns.current_identity.id

      case Accounts.get_identity(id) do
        nil ->
          conn |> put_status(:not_found) |> json(%{error: "account.not_found"})

        identity ->
          handle_account_action(conn, identity, action, admin_id, params)
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  defp handle_account_action(conn, identity, "suspend", admin_id, _params) do
    case identity
         |> Hybridsocial.Accounts.Identity.suspend_changeset()
         |> Hybridsocial.Repo.update() do
      {:ok, updated} ->
        Moderation.log(admin_id, "account.suspended", "identity", identity.id, %{})
        conn |> put_status(:ok) |> json(%{data: serialize_account(updated)})

      {:error, _} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "account.action_failed"})
    end
  end

  defp handle_account_action(conn, identity, "unsuspend", admin_id, _params) do
    case identity
         |> Hybridsocial.Accounts.Identity.unsuspend_changeset()
         |> Hybridsocial.Repo.update() do
      {:ok, updated} ->
        Moderation.log(admin_id, "account.unsuspended", "identity", identity.id, %{})
        conn |> put_status(:ok) |> json(%{data: serialize_account(updated)})

      {:error, _} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "account.action_failed"})
    end
  end

  defp handle_account_action(conn, identity, "warn", admin_id, params) do
    Moderation.log(admin_id, "account.warned", "identity", identity.id, %{
      reason: params["reason"] || ""
    })

    conn
    |> put_status(:ok)
    |> json(%{data: serialize_account(identity), message: "account.warned"})
  end

  defp handle_account_action(conn, _identity, _action, _admin_id, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "account.invalid_action"})
  end

  # ── Content Filters ──────────────────────────────────────────────────

  def list_filters(conn, _params) do
    with :ok <- require_permission(conn, "content.filter_manage") do
      filters = Moderation.list_filters()

      conn
      |> put_status(:ok)
      |> json(%{data: Enum.map(filters, &serialize_filter/1)})
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def create_filter(conn, params) do
    with :ok <- require_permission(conn, "content.filter_manage") do
      admin_id = conn.assigns.current_identity.id
      attrs = Map.put(params, "created_by", admin_id)

      case Moderation.create_filter(attrs) do
        {:ok, filter} ->
          Moderation.log(admin_id, "content_filter.created", "content_filter", filter.id, %{
            type: filter.type,
            pattern: filter.pattern,
            action: filter.action
          })

          conn |> put_status(:created) |> json(%{data: serialize_filter(filter)})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "validation.failed", details: format_errors(changeset)})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def delete_filter(conn, %{"id" => id}) do
    with :ok <- require_permission(conn, "content.filter_manage") do
      admin_id = conn.assigns.current_identity.id

      case Moderation.delete_filter(id) do
        {:ok, _} ->
          Moderation.log(admin_id, "content_filter.deleted", "content_filter", id, %{})
          conn |> put_status(:ok) |> json(%{message: "filter.deleted"})

        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "filter.not_found"})

        {:error, _} ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: "filter.delete_failed"})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  # ── Banned Domains ───────────────────────────────────────────────────

  def list_banned_domains(conn, _params) do
    with :ok <- require_permission(conn, "federation.manage") do
      domains = Moderation.list_banned_domains()

      conn
      |> put_status(:ok)
      |> json(%{data: Enum.map(domains, &serialize_banned_domain/1)})
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def ban_domain(conn, %{"domain" => domain, "type" => type} = params) do
    with :ok <- require_permission(conn, "federation.manage") do
      admin_id = conn.assigns.current_identity.id
      reason = params["reason"]

      case Moderation.ban_domain(domain, type, reason, admin_id) do
        {:ok, banned_domain} ->
          conn |> put_status(:created) |> json(%{data: serialize_banned_domain(banned_domain)})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "validation.failed", details: format_errors(changeset)})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def unban_domain(conn, %{"domain" => domain}) do
    with :ok <- require_permission(conn, "federation.manage") do
      admin_id = conn.assigns.current_identity.id

      case Moderation.unban_domain(domain, admin_id) do
        :ok ->
          conn |> put_status(:ok) |> json(%{message: "domain.unbanned"})

        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "domain.not_found"})

        {:error, _} ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: "domain.unban_failed"})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  # ── Relays ──────────────────────────────────────────────────────────

  alias Hybridsocial.Federation.Relays

  def list_relays(conn, _params) do
    with :ok <- require_permission(conn, "federation.relay_manage") do
      relays = Relays.list_relays()

      conn
      |> put_status(:ok)
      |> json(%{data: Enum.map(relays, &serialize_relay/1)})
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def subscribe_relay(conn, %{"inbox_url" => inbox_url}) do
    with :ok <- require_permission(conn, "federation.relay_manage") do
      admin_id = conn.assigns.current_identity.id

      case Relays.subscribe_to_relay(inbox_url, admin_id) do
        {:ok, relay} ->
          Moderation.log(admin_id, "relay.subscribed", "relay", relay.id, %{inbox_url: inbox_url})
          conn |> put_status(:created) |> json(%{data: serialize_relay(relay)})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "validation.failed", details: format_errors(changeset)})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def unsubscribe_relay(conn, %{"id" => id}) do
    with :ok <- require_permission(conn, "federation.relay_manage") do
      admin_id = conn.assigns.current_identity.id

      case Relays.unsubscribe_from_relay(id, admin_id) do
        {:ok, _} ->
          Moderation.log(admin_id, "relay.unsubscribed", "relay", id, %{})
          conn |> put_status(:ok) |> json(%{message: "relay.unsubscribed"})

        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "relay.not_found"})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  # ── Serializers ──────────────────────────────────────────────────────

  defp serialize_report(report) do
    %{
      id: report.id,
      reporter_id: report.reporter_id,
      reported_id: report.reported_id,
      target_type: report.target_type,
      target_id: report.target_id,
      category: report.category,
      description: report.description,
      status: report.status,
      assigned_to: report.assigned_to,
      action_taken: report.action_taken,
      federated: report.federated,
      resolved_at: report.resolved_at,
      created_at: report.inserted_at
    }
  end

  defp serialize_audit_entry(entry) do
    %{
      id: entry.id,
      actor_id: entry.actor_id,
      action: entry.action,
      target_type: entry.target_type,
      target_id: entry.target_id,
      details: entry.details,
      ip_address: entry.ip_address,
      created_at: entry.created_at
    }
  end

  defp serialize_account(identity) do
    %{
      id: identity.id,
      handle: identity.handle,
      display_name: identity.display_name,
      type: identity.type,
      is_suspended: identity.is_suspended,
      is_admin: identity.is_admin,
      created_at: identity.inserted_at
    }
  end

  defp serialize_filter(filter) do
    %{
      id: filter.id,
      type: filter.type,
      pattern: filter.pattern,
      action: filter.action,
      replacement: filter.replacement,
      context: filter.context,
      created_at: filter.inserted_at
    }
  end

  defp serialize_banned_domain(domain) do
    %{
      domain: domain.domain,
      type: domain.type,
      reason: domain.reason,
      created_at: domain.inserted_at
    }
  end

  defp serialize_relay(relay) do
    %{
      id: relay.id,
      inbox_url: relay.inbox_url,
      status: relay.status,
      created_at: relay.inserted_at
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  defp parse_int(nil, default), do: default

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_int(val, _default) when is_integer(val), do: val
end
