defmodule HybridsocialWeb.Api.V1.AdminController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Moderation
  alias Hybridsocial.Federation
  alias Hybridsocial.Accounts
  alias Hybridsocial.Social.Posts
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

      pairs =
        stats
        |> String.trim()
        |> String.split(",")
        |> Enum.map(fn pair ->
          [k, v] = String.split(pair, "=")
          {k, v}
        end)
        |> Map.new()

      %{db: String.trim(db), keys: pairs["keys"] || "0", expires: pairs["expires"] || "0"}
    end)
  end

  defp check_opensearch do
    url = Application.get_env(:hybridsocial, :opensearch_url, "http://localhost:9200")

    try do
      cluster_info = os_fetch_json(url)
      health = os_fetch_json("#{url}/_cluster/health")
      indices = os_fetch_indices(url)

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

  defp os_fetch_json(url) do
    case HTTPoison.get(url, [], recv_timeout: 5_000, timeout: 5_000) do
      {:ok, %{status_code: 200, body: body}} -> Jason.decode!(body)
      _ -> nil
    end
  end

  defp os_fetch_indices(url) do
    case HTTPoison.get("#{url}/_cat/indices?format=json", [],
           recv_timeout: 5_000,
           timeout: 5_000
         ) do
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

          _ ->
            []
        end

      _ ->
        []
    end
  end

  defp check_nats do
    nats_host = Application.get_env(:hybridsocial, :nats_host, "localhost")
    nats_port = Application.get_env(:hybridsocial, :nats_port, 4222)
    monitoring_port = Application.get_env(:hybridsocial, :nats_monitoring_port, 8222)

    try do
      port_status = nats_check_port(nats_host, nats_port)

      if port_status == :up do
        server_info = nats_monitoring_fetch(nats_host, monitoring_port, "/varz")
        jetstream_info = nats_monitoring_fetch(nats_host, monitoring_port, "/jsz")
        nats_build_status(server_info, jetstream_info)
      else
        %{status: "down", error: "Cannot connect to NATS on port #{nats_port}"}
      end
    rescue
      e -> %{status: "down", error: Exception.message(e)}
    end
  end

  defp nats_check_port(host, port) do
    case :gen_tcp.connect(to_charlist(host), port, [], 3_000) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        :up

      {:error, _} ->
        :down
    end
  end

  defp nats_monitoring_fetch(host, port, path) do
    case HTTPoison.get("http://#{host}:#{port}#{path}", [],
           recv_timeout: 3_000,
           timeout: 3_000
         ) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} -> data
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp nats_build_status(server_info, jetstream_info) do
    app_connected = Hybridsocial.Nats.connected?()

    %{
      status: "up",
      integration: if(app_connected, do: "active", else: "connecting"),
      app_connected: app_connected,
      note:
        if(app_connected,
          do:
            "NATS connected. JetStream handling federation delivery, real-time streaming, and background jobs.",
          else: "NATS server running. Application connecting..."
        )
    }
    |> maybe_merge_server_info(server_info)
    |> maybe_merge_jetstream_info(jetstream_info)
  end

  defp maybe_merge_server_info(result, nil), do: result

  defp maybe_merge_server_info(result, info) do
    Map.merge(result, %{
      version: info["version"] || "unknown",
      uptime_seconds: info["uptime"] || 0,
      connections: info["connections"] || 0,
      total_messages: info["in_msgs"] || 0,
      total_bytes: info["in_bytes"] || 0
    })
  end

  defp maybe_merge_jetstream_info(result, nil), do: Map.put(result, :jetstream_enabled, false)

  defp maybe_merge_jetstream_info(result, info) do
    Map.merge(result, %{
      jetstream_enabled: true,
      js_streams: info["streams"] || 0,
      js_consumers: info["consumers"] || 0,
      js_memory: info["memory"] || 0,
      js_storage: info["storage"] || 0
    })
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
      account:
        if(identity,
          do: %{
            id: identity.id,
            handle: identity.handle,
            display_name: identity.display_name,
            avatar_url: identity.avatar_url
          }
        )
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
        "silence" -> "users.moderate"
        "unsilence" -> "users.moderate"
        "shadow_ban" -> "users.moderate"
        "unshadow_ban" -> "users.moderate"
        "force_sensitive" -> "users.moderate"
        "unforce_sensitive" -> "users.moderate"
        "revoke_all_sessions" -> "users.moderate"
        "warn" -> "users.warn"
        "update" -> "users.edit"
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

  defp handle_account_action(conn, identity, "update", admin_id, params) do
    update_attrs =
      Map.take(params, ["display_name", "bio", "avatar_url", "header_url", "verification_tier"])

    case Accounts.admin_update_identity(identity, update_attrs) do
      {:ok, updated} ->
        Moderation.log(admin_id, "account.updated", "identity", identity.id, update_attrs)
        conn |> put_status(:ok) |> json(%{data: serialize_account(updated)})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  defp handle_account_action(conn, identity, "silence", admin_id, params) do
    silence_attrs = %{
      "silenced_until" => params["silenced_until"],
      "silence_reason" => params["reason"]
    }

    case Accounts.silence_identity(identity, silence_attrs) do
      {:ok, updated} ->
        Moderation.log(admin_id, "account.silenced", "identity", identity.id, %{
          reason: params["reason"] || "",
          silenced_until: params["silenced_until"]
        })

        conn |> put_status(:ok) |> json(%{data: serialize_account(updated)})

      {:error, _} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "account.action_failed"})
    end
  end

  defp handle_account_action(conn, identity, "unsilence", admin_id, params) do
    case Accounts.unsilence_identity(identity) do
      {:ok, updated} ->
        Moderation.log(admin_id, "account.unsilenced", "identity", identity.id, %{
          reason: params["reason"] || ""
        })

        conn |> put_status(:ok) |> json(%{data: serialize_account(updated)})

      {:error, _} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "account.action_failed"})
    end
  end

  defp handle_account_action(conn, identity, "shadow_ban", admin_id, params) do
    case Accounts.shadow_ban_identity(identity) do
      {:ok, updated} ->
        Moderation.log(admin_id, "account.shadow_banned", "identity", identity.id, %{
          reason: params["reason"] || ""
        })

        conn |> put_status(:ok) |> json(%{data: serialize_account(updated)})

      {:error, _} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "account.action_failed"})
    end
  end

  defp handle_account_action(conn, identity, "unshadow_ban", admin_id, params) do
    case Accounts.unshadow_ban_identity(identity) do
      {:ok, updated} ->
        Moderation.log(admin_id, "account.unshadow_banned", "identity", identity.id, %{
          reason: params["reason"] || ""
        })

        conn |> put_status(:ok) |> json(%{data: serialize_account(updated)})

      {:error, _} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "account.action_failed"})
    end
  end

  defp handle_account_action(conn, identity, "force_sensitive", admin_id, params) do
    case Accounts.force_sensitive_identity(identity) do
      {:ok, updated} ->
        Moderation.log(admin_id, "account.force_sensitive", "identity", identity.id, %{
          reason: params["reason"] || ""
        })

        conn |> put_status(:ok) |> json(%{data: serialize_account(updated)})

      {:error, _} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "account.action_failed"})
    end
  end

  defp handle_account_action(conn, identity, "unforce_sensitive", admin_id, params) do
    case Accounts.unforce_sensitive_identity(identity) do
      {:ok, updated} ->
        Moderation.log(admin_id, "account.unforce_sensitive", "identity", identity.id, %{
          reason: params["reason"] || ""
        })

        conn |> put_status(:ok) |> json(%{data: serialize_account(updated)})

      {:error, _} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "account.action_failed"})
    end
  end

  defp handle_account_action(conn, identity, "revoke_all_sessions", admin_id, params) do
    {count, _} = Accounts.admin_revoke_all_tokens(identity.id)

    Moderation.log(admin_id, "account.sessions_revoked", "identity", identity.id, %{
      reason: params["reason"] || "",
      revoked_count: count
    })

    conn
    |> put_status(:ok)
    |> json(%{
      data: serialize_account(identity),
      message: "account.sessions_revoked",
      revoked_count: count
    })
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

  # ── Instance Policies ────────────────────────────────────────────────

  def list_instance_policies(conn, _params) do
    with :ok <- require_permission(conn, "federation.manage") do
      policies = Federation.list_instance_policies()

      conn
      |> put_status(:ok)
      |> json(%{data: Enum.map(policies, &serialize_instance_policy/1)})
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def create_instance_policy(conn, %{"domain" => domain} = params) do
    with :ok <- require_permission(conn, "federation.manage") do
      admin_id = conn.assigns.current_identity.id
      policy = params["policy_type"] || params["policy"]
      reason = params["reason"]

      case Federation.set_instance_policy(domain, policy, reason, admin_id) do
        {:ok, instance_policy} ->
          Moderation.log(admin_id, "instance_policy.created", "instance_policy", domain, %{
            domain: domain,
            policy: policy,
            reason: reason
          })

          conn
          |> put_status(:created)
          |> json(%{data: serialize_instance_policy(instance_policy)})

        {:error, %Ecto.Changeset{} = changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "validation.failed", details: format_errors(changeset)})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def update_instance_policy(conn, %{"id" => domain} = params) do
    with :ok <- require_permission(conn, "federation.manage") do
      admin_id = conn.assigns.current_identity.id

      case Federation.get_instance_policy(domain) do
        nil ->
          conn |> put_status(:not_found) |> json(%{error: "instance_policy.not_found"})

        _existing ->
          policy = params["policy_type"] || params["policy"]
          reason = params["reason"]

          case Federation.set_instance_policy(domain, policy, reason, admin_id) do
            {:ok, updated} ->
              Moderation.log(
                admin_id,
                "instance_policy.updated",
                "instance_policy",
                domain,
                %{
                  domain: domain,
                  policy: policy,
                  reason: reason
                }
              )

              conn |> put_status(:ok) |> json(%{data: serialize_instance_policy(updated)})

            {:error, %Ecto.Changeset{} = changeset} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{error: "validation.failed", details: format_errors(changeset)})
          end
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def delete_instance_policy(conn, %{"id" => domain}) do
    with :ok <- require_permission(conn, "federation.manage") do
      admin_id = conn.assigns.current_identity.id

      case Federation.delete_instance_policy(domain) do
        {:ok, _} ->
          Moderation.log(admin_id, "instance_policy.deleted", "instance_policy", domain, %{
            domain: domain
          })

          conn |> put_status(:ok) |> json(%{message: "instance_policy.deleted"})

        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "instance_policy.not_found"})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  # ── Webhooks ────────────────────────────────────────────────────────

  def list_webhooks(conn, _params) do
    with :ok <- require_permission(conn, "settings.manage") do
      webhooks = Moderation.list_webhooks()

      conn
      |> put_status(:ok)
      |> json(%{data: Enum.map(webhooks, &serialize_webhook/1)})
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def create_webhook(conn, params) do
    with :ok <- require_permission(conn, "settings.manage") do
      admin_id = conn.assigns.current_identity.id
      attrs = Map.put(params, "created_by", admin_id)

      case Moderation.create_webhook(attrs) do
        {:ok, webhook} ->
          Moderation.log(admin_id, "webhook.created", "webhook", webhook.id, %{
            url: webhook.url,
            events: webhook.events
          })

          conn |> put_status(:created) |> json(%{data: serialize_webhook(webhook)})

        {:error, %Ecto.Changeset{} = changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "validation.failed", details: format_errors(changeset)})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def update_webhook(conn, %{"id" => id} = params) do
    with :ok <- require_permission(conn, "settings.manage") do
      admin_id = conn.assigns.current_identity.id
      attrs = Map.drop(params, ["id"])

      case Moderation.update_webhook(id, attrs) do
        {:ok, webhook} ->
          Moderation.log(admin_id, "webhook.updated", "webhook", webhook.id, %{
            url: webhook.url,
            events: webhook.events
          })

          conn |> put_status(:ok) |> json(%{data: serialize_webhook(webhook)})

        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "webhook.not_found"})

        {:error, %Ecto.Changeset{} = changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "validation.failed", details: format_errors(changeset)})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def delete_webhook(conn, %{"id" => id}) do
    with :ok <- require_permission(conn, "settings.manage") do
      admin_id = conn.assigns.current_identity.id

      case Moderation.delete_webhook(id) do
        {:ok, webhook} ->
          Moderation.log(admin_id, "webhook.deleted", "webhook", id, %{
            url: webhook.url
          })

          conn |> put_status(:ok) |> json(%{message: "webhook.deleted"})

        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "webhook.not_found"})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  # ── IP Bans ─────────────────────────────────────────────────────────

  def list_ip_bans(conn, _params) do
    with :ok <- require_permission(conn, "users.suspend") do
      bans = Moderation.list_ip_bans()

      conn
      |> put_status(:ok)
      |> json(%{data: Enum.map(bans, &serialize_ip_ban/1)})
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def create_ip_ban(conn, params) do
    with :ok <- require_permission(conn, "users.suspend") do
      admin_id = conn.assigns.current_identity.id

      attrs = %{
        "ip_address" => params["ip_address"],
        "subnet_mask" => params["subnet_mask"],
        "reason" => params["reason"],
        "expires_at" => params["expires_at"],
        "created_by" => admin_id
      }

      case Moderation.create_ip_ban(attrs) do
        {:ok, ban} ->
          Moderation.log(admin_id, "ip_ban.created", "ip_ban", ban.id, %{
            ip_address: ban.ip_address,
            subnet_mask: ban.subnet_mask,
            reason: ban.reason
          })

          conn |> put_status(:created) |> json(%{data: serialize_ip_ban(ban)})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "validation.failed", details: format_errors(changeset)})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def delete_ip_ban(conn, %{"id" => id}) do
    with :ok <- require_permission(conn, "users.suspend") do
      admin_id = conn.assigns.current_identity.id

      case Moderation.delete_ip_ban(id) do
        {:ok, _} ->
          Moderation.log(admin_id, "ip_ban.deleted", "ip_ban", id, %{})
          conn |> put_status(:ok) |> json(%{message: "ip_ban.deleted"})

        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "ip_ban.not_found"})

        {:error, _} ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: "ip_ban.delete_failed"})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  # ── Email Domain Bans ──────────────────────────────────────────────

  def list_email_domain_bans(conn, _params) do
    with :ok <- require_permission(conn, "users.manage") do
      bans = Moderation.list_email_domain_bans()

      conn
      |> put_status(:ok)
      |> json(%{data: Enum.map(bans, &serialize_email_domain_ban/1)})
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def create_email_domain_ban(conn, params) do
    with :ok <- require_permission(conn, "users.manage") do
      admin_id = conn.assigns.current_identity.id

      attrs = %{
        "domain" => params["domain"],
        "reason" => params["reason"],
        "created_by" => admin_id
      }

      case Moderation.create_email_domain_ban(attrs) do
        {:ok, ban} ->
          Moderation.log(admin_id, "email_domain_ban.created", "email_domain_ban", ban.id, %{
            domain: ban.domain,
            reason: ban.reason
          })

          conn |> put_status(:created) |> json(%{data: serialize_email_domain_ban(ban)})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "validation.failed", details: format_errors(changeset)})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def delete_email_domain_ban(conn, %{"id" => id}) do
    with :ok <- require_permission(conn, "users.manage") do
      admin_id = conn.assigns.current_identity.id

      case Moderation.delete_email_domain_ban(id) do
        {:ok, _} ->
          Moderation.log(admin_id, "email_domain_ban.deleted", "email_domain_ban", id, %{})
          conn |> put_status(:ok) |> json(%{message: "email_domain_ban.deleted"})

        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "email_domain_ban.not_found"})

        {:error, _} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "email_domain_ban.delete_failed"})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  # ── Appeals (Admin) ──────────────────────────────────────────────────

  def list_appeals(conn, params) do
    with :ok <- require_permission(conn, "users.manage") do
      opts = [
        status: params["status"],
        limit: clamp_limit(params["limit"]),
        offset: parse_int(params["offset"], 0)
      ]

      appeals = Moderation.list_appeals(opts)

      conn
      |> put_status(:ok)
      |> json(%{data: Enum.map(appeals, &serialize_appeal/1)})
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def approve_appeal(conn, %{"id" => id} = params) do
    with :ok <- require_permission(conn, "users.manage") do
      admin_id = conn.assigns.current_identity.id
      response = params["response"]

      case Moderation.approve_appeal(id, admin_id, response) do
        {:ok, appeal} ->
          conn |> put_status(:ok) |> json(%{data: serialize_appeal(appeal)})

        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "appeal.not_found"})

        {:error, :already_reviewed} ->
          conn |> put_status(:conflict) |> json(%{error: "appeal.already_reviewed"})

        {:error, _} ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: "appeal.approve_failed"})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def reject_appeal(conn, %{"id" => id} = params) do
    with :ok <- require_permission(conn, "users.manage") do
      admin_id = conn.assigns.current_identity.id
      response = params["response"]

      case Moderation.reject_appeal(id, admin_id, response) do
        {:ok, appeal} ->
          conn |> put_status(:ok) |> json(%{data: serialize_appeal(appeal)})

        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "appeal.not_found"})

        {:error, :already_reviewed} ->
          conn |> put_status(:conflict) |> json(%{error: "appeal.already_reviewed"})

        {:error, _} ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: "appeal.reject_failed"})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  # ── Moderation Notes ────────────────────────────────────────────────

  def list_moderation_notes(conn, %{"id" => identity_id}) do
    with :ok <- require_permission(conn, "users.view") do
      notes = Moderation.list_moderation_notes(identity_id)

      conn
      |> put_status(:ok)
      |> json(%{data: Enum.map(notes, &serialize_moderation_note/1)})
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def create_moderation_note(conn, %{"id" => identity_id} = params) do
    with :ok <- require_permission(conn, "users.manage") do
      admin_id = conn.assigns.current_identity.id

      attrs = %{
        "target_identity_id" => identity_id,
        "author_id" => admin_id,
        "content" => params["content"]
      }

      case Moderation.create_moderation_note(attrs) do
        {:ok, note} ->
          Moderation.log(admin_id, "moderation_note.created", "moderation_note", note.id, %{
            target_identity_id: identity_id
          })

          conn |> put_status(:created) |> json(%{data: serialize_moderation_note(note)})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "validation.failed", details: format_errors(changeset)})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def delete_moderation_note(conn, %{"id" => id}) do
    with :ok <- require_permission(conn, "users.manage") do
      admin_id = conn.assigns.current_identity.id

      case Moderation.delete_moderation_note(id) do
        {:ok, _} ->
          Moderation.log(admin_id, "moderation_note.deleted", "moderation_note", id, %{})
          conn |> put_status(:ok) |> json(%{message: "moderation_note.deleted"})

        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "moderation_note.not_found"})

        {:error, _} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "moderation_note.delete_failed"})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  # ── Admin Post Management ──────────────────────────────────────────

  def show_post(conn, %{"id" => id}) do
    with :ok <- require_permission(conn, "content.manage") do
      case Posts.admin_get_post(id) do
        {:ok, post} ->
          conn |> put_status(:ok) |> json(%{data: serialize_post(post)})

        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "post.not_found"})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def delete_post(conn, %{"id" => id} = params) do
    with :ok <- require_permission(conn, "content.manage") do
      admin_id = conn.assigns.current_identity.id
      reason = params["reason"] || ""

      case Posts.admin_delete_post(id, admin_id, reason) do
        {:ok, post} ->
          conn |> put_status(:ok) |> json(%{data: serialize_post(post)})

        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "post.not_found"})

        {:error, _} ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: "post.delete_failed"})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def force_sensitive(conn, %{"id" => id}) do
    with :ok <- require_permission(conn, "content.manage") do
      admin_id = conn.assigns.current_identity.id

      case Posts.admin_force_sensitive(id, admin_id) do
        {:ok, post} ->
          conn |> put_status(:ok) |> json(%{data: serialize_post(post)})

        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "post.not_found"})

        {:error, _} ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: "post.update_failed"})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def remove_sensitive(conn, %{"id" => id}) do
    with :ok <- require_permission(conn, "content.manage") do
      admin_id = conn.assigns.current_identity.id

      case Posts.admin_remove_sensitive(id, admin_id) do
        {:ok, post} ->
          conn |> put_status(:ok) |> json(%{data: serialize_post(post)})

        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "post.not_found"})

        {:error, _} ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: "post.update_failed"})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  # ── Moderation Queue ──────────────────────────────────────────────────

  def list_moderation_queue(conn, params) do
    with :ok <- require_permission(conn, "content.manage") do
      opts = [
        status: params["status"],
        item_type: params["item_type"],
        severity: params["severity"],
        limit: clamp_limit(params["limit"]),
        offset: parse_int(params["offset"], 0)
      ]

      items = Moderation.list_queue(opts)

      conn
      |> put_status(:ok)
      |> json(%{data: Enum.map(items, &serialize_queued_item/1)})
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def moderation_queue_stats(conn, _params) do
    with :ok <- require_permission(conn, "content.manage") do
      stats = Moderation.queue_stats()

      conn
      |> put_status(:ok)
      |> json(%{data: stats})
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def approve_queued_item(conn, %{"id" => id}) do
    with :ok <- require_permission(conn, "content.manage") do
      admin_id = conn.assigns.current_identity.id

      case Moderation.approve_queued_item(id, admin_id) do
        {:ok, item} ->
          Moderation.log(admin_id, "queue_item.approved", "queued_item", id, %{
            item_type: item.item_type,
            item_id: item.item_id
          })

          conn |> put_status(:ok) |> json(%{data: serialize_queued_item(item)})

        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "queued_item.not_found"})

        {:error, :already_reviewed} ->
          conn |> put_status(:conflict) |> json(%{error: "queued_item.already_reviewed"})

        {:error, _} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "queued_item.approve_failed"})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def reject_queued_item(conn, %{"id" => id} = params) do
    with :ok <- require_permission(conn, "content.manage") do
      admin_id = conn.assigns.current_identity.id
      reason = params["reason"] || ""

      case Moderation.reject_queued_item(id, admin_id, reason) do
        {:ok, item} ->
          Moderation.log(admin_id, "queue_item.rejected", "queued_item", id, %{
            item_type: item.item_type,
            item_id: item.item_id,
            reason: reason
          })

          conn |> put_status(:ok) |> json(%{data: serialize_queued_item(item)})

        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "queued_item.not_found"})

        {:error, :already_reviewed} ->
          conn |> put_status(:conflict) |> json(%{error: "queued_item.already_reviewed"})

        {:error, _} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "queued_item.reject_failed"})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def escalate_queued_item(conn, %{"id" => id}) do
    with :ok <- require_permission(conn, "content.manage") do
      admin_id = conn.assigns.current_identity.id

      case Moderation.escalate_queued_item(id, admin_id) do
        {:ok, item} ->
          conn |> put_status(:ok) |> json(%{data: serialize_queued_item(item)})

        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "queued_item.not_found"})

        {:error, :cannot_escalate} ->
          conn |> put_status(:conflict) |> json(%{error: "queued_item.cannot_escalate"})

        {:error, _} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "queued_item.escalate_failed"})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  # ── Defederation Cleanup ─────────────────────────────────────────────

  alias Hybridsocial.Federation.Cleanup

  def purge_instance_content(conn, %{"id" => domain}) do
    with :ok <- require_permission(conn, "federation.manage") do
      admin_id = conn.assigns.current_identity.id

      case Federation.get_instance_policy(domain) do
        nil ->
          conn |> put_status(:not_found) |> json(%{error: "instance_policy.not_found"})

        %{policy: "suspend"} ->
          {:ok, stats} = Cleanup.purge_instance_content(domain)

          Moderation.log(
            admin_id,
            "instance.content_purged",
            "instance_policy",
            domain,
            stats
          )

          conn |> put_status(:ok) |> json(%{data: stats})

        _policy ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "instance_policy.not_suspended"})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def purge_instance_preview(conn, %{"id" => domain}) do
    with :ok <- require_permission(conn, "federation.manage") do
      case Federation.get_instance_policy(domain) do
        nil ->
          conn |> put_status(:not_found) |> json(%{error: "instance_policy.not_found"})

        _policy ->
          {:ok, stats} = Cleanup.purge_instance_content(domain, dry_run: true)
          conn |> put_status(:ok) |> json(%{data: stats})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  # ── Media Hash Bans ─────────────────────────────────────────────────

  def list_media_hash_bans(conn, _params) do
    with :ok <- require_permission(conn, "content.manage") do
      bans = Moderation.list_media_hash_bans()

      conn
      |> put_status(:ok)
      |> json(%{data: Enum.map(bans, &serialize_media_hash_ban/1)})
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def create_media_hash_ban(conn, params) do
    with :ok <- require_permission(conn, "content.manage") do
      admin_id = conn.assigns.current_identity.id

      attrs = %{
        "hash" => params["hash"],
        "hash_type" => params["hash_type"] || "sha256",
        "description" => params["description"],
        "created_by" => admin_id
      }

      case Moderation.create_media_hash_ban(attrs) do
        {:ok, ban} ->
          Moderation.log(admin_id, "media_hash_ban.created", "media_hash_ban", ban.id, %{
            hash: ban.hash,
            hash_type: ban.hash_type,
            description: ban.description
          })

          conn |> put_status(:created) |> json(%{data: serialize_media_hash_ban(ban)})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "validation.failed", details: format_errors(changeset)})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def create_media_hash_ban_from_post(conn, %{"post_id" => post_id}) do
    with :ok <- require_permission(conn, "content.manage") do
      admin_id = conn.assigns.current_identity.id
      do_ban_post_media(conn, post_id, admin_id)
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  defp do_ban_post_media(conn, post_id, admin_id) do
    case Hybridsocial.Social.Posts.get_post(post_id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "post.not_found"})

      post ->
        media_files = get_post_media(post)

        if media_files == [] do
          conn |> put_status(:unprocessable_entity) |> json(%{error: "post.no_media"})
        else
          bans = ban_media_files(media_files, admin_id)

          Moderation.log(admin_id, "media_hash_ban.from_post", "post", post_id, %{
            bans_created: length(bans)
          })

          conn
          |> put_status(:created)
          |> json(%{data: Enum.map(bans, &serialize_media_hash_ban/1)})
        end
    end
  end

  defp ban_media_files(media_files, admin_id) do
    Enum.reduce(media_files, [], fn media_file, acc ->
      case compute_and_ban_media(media_file, admin_id) do
        {:ok, ban} -> [ban | acc]
        _ -> acc
      end
    end)
  end

  defp get_post_media(post) do
    import Ecto.Query
    alias Hybridsocial.Media.MediaFile

    post_time = post.inserted_at
    window_start = DateTime.add(post_time, -60, :second)
    window_end = DateTime.add(post_time, 60, :second)

    MediaFile
    |> where([m], m.identity_id == ^post.identity_id)
    |> where([m], m.inserted_at >= ^window_start and m.inserted_at <= ^window_end)
    |> where([m], is_nil(m.deleted_at))
    |> Hybridsocial.Repo.all()
  end

  defp compute_and_ban_media(media_file, admin_id) do
    alias Hybridsocial.Media.Storage

    storage_path = media_file.storage_path

    case Hybridsocial.Media.Hash.compute_hash(Storage.uploads_dir() <> "/" <> storage_path) do
      {:ok, hash} ->
        attrs = %{
          "hash" => hash,
          "hash_type" => "sha256",
          "description" => "Banned from post media",
          "created_by" => admin_id
        }

        Moderation.create_media_hash_ban(attrs)

      _ ->
        {:error, :hash_failed}
    end
  end

  def delete_media_hash_ban(conn, %{"id" => id}) do
    with :ok <- require_permission(conn, "content.manage") do
      admin_id = conn.assigns.current_identity.id

      case Moderation.delete_media_hash_ban(id) do
        {:ok, _} ->
          Moderation.log(admin_id, "media_hash_ban.deleted", "media_hash_ban", id, %{})
          conn |> put_status(:ok) |> json(%{message: "media_hash_ban.deleted"})

        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "media_hash_ban.not_found"})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  # ── Serializers ──────────────────────────────────────────────────────

  defp serialize_media_hash_ban(ban) do
    %{
      id: ban.id,
      hash: ban.hash,
      hash_type: ban.hash_type,
      description: ban.description,
      created_by: ban.created_by,
      created_at: ban.inserted_at
    }
  end

  defp serialize_post(post) do
    %{
      id: post.id,
      content: post.content,
      content_html: post.content_html,
      post_type: post.post_type,
      visibility: post.visibility,
      sensitive: post.sensitive,
      spoiler_text: post.spoiler_text,
      language: post.language,
      identity_id: post.identity_id,
      parent_id: post.parent_id,
      root_id: post.root_id,
      quote_id: post.quote_id,
      ap_id: post.ap_id,
      reply_count: post.reply_count,
      boost_count: post.boost_count,
      reaction_count: post.reaction_count,
      is_pinned: post.is_pinned,
      published_at: post.published_at,
      edited_at: post.edited_at,
      deleted_at: post.deleted_at,
      created_at: post.inserted_at,
      identity:
        if(Ecto.assoc_loaded?(post.identity) && post.identity,
          do: %{
            id: post.identity.id,
            handle: post.identity.handle,
            display_name: post.identity.display_name
          }
        )
    }
  end

  defp serialize_queued_item(item) do
    %{
      id: item.id,
      item_type: item.item_type,
      item_id: item.item_id,
      source: item.source,
      reason: item.reason,
      severity: item.severity,
      status: item.status,
      reviewed_by: item.reviewed_by,
      reviewed_at: item.reviewed_at,
      created_at: item.inserted_at,
      updated_at: item.updated_at
    }
  end

  defp serialize_appeal(appeal) do
    %{
      id: appeal.id,
      identity_id: appeal.identity_id,
      action_type: appeal.action_type,
      reason: appeal.reason,
      status: appeal.status,
      reviewed_by: appeal.reviewed_by,
      reviewed_at: appeal.reviewed_at,
      response: appeal.response,
      created_at: appeal.inserted_at,
      account:
        if(appeal.identity,
          do: %{
            id: appeal.identity.id,
            handle: appeal.identity.handle,
            display_name: appeal.identity.display_name
          }
        )
    }
  end

  defp serialize_moderation_note(note) do
    %{
      id: note.id,
      target_identity_id: note.target_identity_id,
      author_id: note.author_id,
      content: note.content,
      created_at: note.inserted_at,
      author:
        if(note.author,
          do: %{
            id: note.author.id,
            handle: note.author.handle,
            display_name: note.author.display_name
          }
        )
    }
  end

  defp serialize_ip_ban(ban) do
    %{
      id: ban.id,
      ip_address: ban.ip_address,
      subnet_mask: ban.subnet_mask,
      reason: ban.reason,
      expires_at: ban.expires_at,
      created_by: ban.created_by,
      created_at: ban.inserted_at
    }
  end

  defp serialize_email_domain_ban(ban) do
    %{
      id: ban.id,
      domain: ban.domain,
      reason: ban.reason,
      created_by: ban.created_by,
      created_at: ban.inserted_at
    }
  end

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
      is_silenced: identity.is_silenced,
      silenced_until: identity.silenced_until,
      silence_reason: identity.silence_reason,
      is_shadow_banned: identity.is_shadow_banned,
      force_sensitive: identity.force_sensitive,
      is_admin: identity.is_admin,
      trust_level: identity.trust_level,
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
      scope: filter.scope,
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

  defp serialize_instance_policy(policy) do
    %{
      domain: policy.domain,
      policy: policy.policy,
      reason: policy.reason,
      created_by: policy.created_by,
      created_at: policy.inserted_at,
      updated_at: policy.updated_at
    }
  end

  defp serialize_webhook(webhook) do
    %{
      id: webhook.id,
      url: webhook.url,
      events: webhook.events,
      enabled: webhook.enabled,
      created_by: webhook.created_by,
      created_at: webhook.inserted_at,
      updated_at: webhook.updated_at
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

  # ── Invite Codes ──────────────────────────────────────────────────

  def list_invites(conn, _params) do
    with :ok <- require_permission(conn, "users.manage") do
      invites = Accounts.list_invites()

      conn
      |> put_status(:ok)
      |> json(%{data: Enum.map(invites, &serialize_invite/1)})
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def create_invite(conn, params) do
    with :ok <- require_permission(conn, "users.manage") do
      admin_id = conn.assigns.current_identity.id

      attrs = %{
        "created_by" => admin_id,
        "max_uses" => params["max_uses"],
        "expires_at" => parse_datetime(params["expires_at"])
      }

      case Accounts.create_invite(attrs) do
        {:ok, invite} ->
          Moderation.log(admin_id, "invite.created", "invite", invite.id, %{
            code: invite.code,
            max_uses: invite.max_uses
          })

          invite = Hybridsocial.Repo.preload(invite, :creator)
          conn |> put_status(:created) |> json(%{data: serialize_invite(invite)})

        {:error, %Ecto.Changeset{} = changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "validation.failed", details: format_errors(changeset)})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  def delete_invite(conn, %{"id" => id}) do
    with :ok <- require_permission(conn, "users.manage") do
      admin_id = conn.assigns.current_identity.id

      case Accounts.disable_invite(id) do
        {:ok, invite} ->
          Moderation.log(admin_id, "invite.disabled", "invite", invite.id, %{code: invite.code})
          conn |> put_status(:ok) |> json(%{message: "invite.disabled"})

        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "invite.not_found"})

        {:error, _} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "invite.delete_failed"})
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_datetime(_), do: nil

  defp serialize_invite(invite) do
    %{
      id: invite.id,
      code: invite.code,
      max_uses: invite.max_uses,
      uses: invite.uses,
      expires_at: invite.expires_at,
      disabled: invite.disabled,
      created_by: if(invite.creator, do: invite.creator.handle, else: nil),
      created_at: invite.inserted_at
    }
  end

  # ── Trust Level ──────────────────────────────────────────────────

  def set_trust_level(conn, %{"id" => id, "trust_level" => level}) do
    with :ok <- require_permission(conn, "users.manage") do
      admin_id = conn.assigns.current_identity.id

      case Accounts.get_identity(id) do
        nil ->
          conn |> put_status(:not_found) |> json(%{error: "account.not_found"})

        identity ->
          trust_level = if is_binary(level), do: String.to_integer(level), else: level

          case Accounts.admin_update_identity(identity, %{"trust_level" => trust_level}) do
            {:ok, updated} ->
              Moderation.log(admin_id, "account.trust_level_set", "identity", id, %{
                trust_level: trust_level
              })

              conn |> put_status(:ok) |> json(%{data: serialize_account(updated)})

            {:error, _} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{error: "account.trust_level_update_failed"})
          end
      end
    else
      {:error, perm} -> deny(conn, perm)
    end
  end
end
