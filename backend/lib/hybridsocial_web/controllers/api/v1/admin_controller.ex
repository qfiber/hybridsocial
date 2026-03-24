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

  # ── Dashboard ─────────────────────────────────────────────────────────

  def dashboard(conn, _params) do
    import Ecto.Query
    alias Hybridsocial.Repo
    alias Hybridsocial.Accounts.Identity
    alias Hybridsocial.Social.Post
    alias Hybridsocial.Moderation.Report

    # Core stats
    total_users =
      Identity
      |> where([i], i.type == "user" and is_nil(i.deleted_at))
      |> Repo.aggregate(:count)

    total_posts =
      Post
      |> where([p], is_nil(p.deleted_at))
      |> Repo.aggregate(:count)

    known_instances =
      Identity
      |> where([i], not is_nil(i.ap_actor_url) and is_nil(i.deleted_at))
      |> select([i], fragment("count(distinct split_part(?, '/', 3))", i.ap_actor_url))
      |> Repo.one() || 0

    open_reports =
      Report
      |> where([r], r.status == "pending")
      |> Repo.aggregate(:count)

    # Service health checks
    services = check_services()

    json(conn, %{
      total_users: total_users,
      total_posts: total_posts,
      known_instances: known_instances,
      open_reports: open_reports,
      services: services
    })
  end

  defp check_services do
    %{
      valkey: check_valkey(),
      opensearch: check_opensearch(),
      nats: check_nats(),
      database: check_database()
    }
  end

  defp check_valkey do
    try do
      case Redix.command(:valkey_0, ["PING"]) do
        {:ok, "PONG"} ->
          {:ok, server_info} = Redix.command(:valkey_0, ["INFO", "server"])
          {:ok, memory_info} = Redix.command(:valkey_0, ["INFO", "memory"])
          {:ok, keyspace_info} = Redix.command(:valkey_0, ["INFO", "keyspace"])
          {:ok, clients_info} = Redix.command(:valkey_0, ["INFO", "clients"])
          {:ok, db_size} = Redix.command(:valkey_0, ["DBSIZE"])

          %{
            status: "up",
            version: parse_info_field(server_info, "redis_version"),
            uptime_seconds: parse_info_int(server_info, "uptime_in_seconds"),
            memory: parse_info_field(memory_info, "used_memory_human"),
            memory_peak: parse_info_field(memory_info, "used_memory_peak_human"),
            total_keys: db_size,
            connected_clients: parse_info_int(clients_info, "connected_clients"),
            keyspace: parse_keyspace(keyspace_info)
          }

        _ ->
          %{status: "down", error: "Unexpected response"}
      end
    rescue
      e -> %{status: "down", error: Exception.message(e)}
    end
  end

  defp parse_info_field(info, field) do
    info
    |> String.split("\n")
    |> Enum.find_value("unknown", fn line ->
      if String.starts_with?(line, "#{field}:") do
        line |> String.split(":", parts: 2) |> List.last() |> String.trim()
      end
    end)
  end

  defp parse_info_int(info, field) do
    case parse_info_field(info, field) do
      "unknown" -> 0
      val -> String.to_integer(val)
    end
  end

  defp parse_keyspace(info) do
    # Parse lines like "db0:keys=42,expires=10,avg_ttl=300000"
    info
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "db"))
    |> Enum.map(fn line ->
      [db, stats] = String.split(line, ":", parts: 2)
      pairs = stats |> String.trim() |> String.split(",") |> Enum.map(fn pair ->
        [k, v] = String.split(pair, "=")
        {k, v}
      end) |> Map.new()
      %{db: String.trim(db), keys: pairs["keys"] || "0", expires: pairs["expires"] || "0"}
    end)
  end

  defp check_opensearch do
    url = Application.get_env(:hybridsocial, :opensearch_url, "http://localhost:9200")

    try do
      # Basic cluster info
      cluster_info = case HTTPoison.get(url, [], recv_timeout: 5_000, timeout: 5_000) do
        {:ok, %{status_code: 200, body: body}} -> Jason.decode!(body)
        _ -> nil
      end

      # Cluster health
      health = case HTTPoison.get("#{url}/_cluster/health", [], recv_timeout: 5_000, timeout: 5_000) do
        {:ok, %{status_code: 200, body: body}} -> Jason.decode!(body)
        _ -> nil
      end

      # Index stats
      indices = case HTTPoison.get("#{url}/_cat/indices?format=json", [], recv_timeout: 5_000, timeout: 5_000) do
        {:ok, %{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, list} when is_list(list) ->
              Enum.map(list, fn idx ->
                %{
                  name: idx["index"],
                  health: idx["health"],
                  docs_count: idx["docs.count"],
                  store_size: idx["store.size"],
                  status: idx["status"]
                }
              end)
            _ -> []
          end
        _ -> []
      end

      if cluster_info do
        %{
          status: if(health && health["status"] == "green", do: "up", else: "degraded"),
          version: get_in(cluster_info, ["version", "number"]) || "unknown",
          cluster_name: cluster_info["cluster_name"] || "unknown",
          cluster_health: health["status"] || "unknown",
          node_count: health["number_of_nodes"] || 0,
          active_shards: health["active_shards"] || 0,
          indices: indices
        }
      else
        %{status: "down", error: "Cannot reach OpenSearch"}
      end
    rescue
      e -> %{status: "down", error: Exception.message(e)}
    end
  end

  defp check_nats do
    nats_host = Application.get_env(:hybridsocial, :nats_host, "localhost")
    nats_port = Application.get_env(:hybridsocial, :nats_port, 4222)
    # NATS monitoring port is typically 8222
    monitoring_port = Application.get_env(:hybridsocial, :nats_monitoring_port, 8222)

    try do
      # Check if NATS client port is reachable
      port_status = case :gen_tcp.connect(to_charlist(nats_host), nats_port, [], 3_000) do
        {:ok, socket} ->
          :gen_tcp.close(socket)
          :up
        {:error, _} ->
          :down
      end

      # Try to get NATS server info from monitoring endpoint
      server_info = case HTTPoison.get("http://#{nats_host}:#{monitoring_port}/varz", [], recv_timeout: 3_000, timeout: 3_000) do
        {:ok, %{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, data} -> data
            _ -> nil
          end
        _ -> nil
      end

      # Try to get JetStream info
      jetstream_info = case HTTPoison.get("http://#{nats_host}:#{monitoring_port}/jsz", [], recv_timeout: 3_000, timeout: 3_000) do
        {:ok, %{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, data} -> data
            _ -> nil
          end
        _ -> nil
      end

      if port_status == :up do
        app_connected = Hybridsocial.Nats.connected?()

        result = %{
          status: "up",
          integration: if(app_connected, do: "active", else: "connecting"),
          app_connected: app_connected,
          note: if(app_connected,
            do: "NATS connected. JetStream handling federation delivery, real-time streaming, and background jobs.",
            else: "NATS server running. Application connecting..."
          )
        }

        result = if server_info do
          Map.merge(result, %{
            version: server_info["version"] || "unknown",
            uptime_seconds: server_info["uptime"] || 0,
            connections: server_info["connections"] || 0,
            total_messages: server_info["in_msgs"] || 0,
            total_bytes: server_info["in_bytes"] || 0
          })
        else
          result
        end

        result = if jetstream_info do
          Map.merge(result, %{
            jetstream_enabled: true,
            js_streams: jetstream_info["streams"] || 0,
            js_consumers: jetstream_info["consumers"] || 0,
            js_memory: jetstream_info["memory"] || 0,
            js_storage: jetstream_info["storage"] || 0
          })
        else
          Map.put(result, :jetstream_enabled, false)
        end

        result
      else
        %{status: "down", error: "Cannot connect to NATS on port #{nats_port}"}
      end
    rescue
      e -> %{status: "down", error: Exception.message(e)}
    end
  end

  defp check_database do
    try do
      case Hybridsocial.Repo.query("SELECT 1") do
        {:ok, _} -> %{status: "up"}
        {:error, e} -> %{status: "down", error: Exception.message(e)}
      end
    rescue
      e -> %{status: "down", error: Exception.message(e)}
    end
  end

  # ── Verifications ────────────────────────────────────────────────────

  def list_verifications(conn, params) do
    with :ok <- require_permission(conn, "users.view") do
      opts = [
        status: params["status"],
        limit: clamp_limit(params["limit"]),
        offset: parse_int(params["offset"], 0)
      ]

      verifications = Hybridsocial.Premium.list_verifications(opts)

      json(conn, %{
        data: Enum.map(verifications, &serialize_verification/1)
      })
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def approve_verification(conn, %{"id" => id}) do
    with :ok <- require_permission(conn, "users.view") do
      admin_id = conn.assigns.current_identity.id

      case Hybridsocial.Premium.approve_verification(id, admin_id) do
        {:ok, verification} ->
          json(conn, %{data: serialize_verification(verification)})

        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "verification.not_found"})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def reject_verification(conn, %{"id" => id}) do
    with :ok <- require_permission(conn, "users.view") do
      admin_id = conn.assigns.current_identity.id

      case Hybridsocial.Premium.reject_verification(id, admin_id) do
        {:ok, verification} ->
          json(conn, %{data: serialize_verification(verification)})

        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "verification.not_found"})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  defp serialize_verification(verification) do
    identity = verification.identity

    %{
      id: verification.id,
      type: verification.type,
      status: verification.status,
      metadata: verification.metadata,
      verified_at: verification.verified_at,
      created_at: verification.inserted_at,
      account: if(identity, do: %{
        id: identity.id,
        handle: identity.handle,
        display_name: identity.display_name,
        avatar_url: identity.avatar_url
      })
    }
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
