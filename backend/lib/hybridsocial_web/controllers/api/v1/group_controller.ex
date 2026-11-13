defmodule HybridsocialWeb.Api.V1.GroupController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Groups
  alias Hybridsocial.Repo
  import HybridsocialWeb.Helpers.Pagination, only: [clamp_limit: 1]

  # POST /api/v1/groups
  def create(conn, params) do
    identity = conn.assigns.current_identity

    case Groups.create_group(identity.id, params) do
      {:ok, group} ->
        conn
        |> put_status(:created)
        |> json(serialize_group(group))

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  # GET /api/v1/groups
  def index(conn, params) do
    groups =
      cond do
        params["q"] ->
          Groups.search_groups(params["q"])

        # `filter=member` → only the groups the viewer has actually joined
        # (share-to-group picker / "My groups" tab). Requires auth; anonymous
        # callers have no memberships, so an empty list.
        params["filter"] == "member" ->
          case viewer_id(conn) do
            nil ->
              []

            vid ->
              opts =
                []
                |> maybe_add_limit(params["limit"])
                |> maybe_add_opt(:cursor, params["cursor"])

              Groups.list_member_groups(vid, opts)
          end

        true ->
          opts =
            []
            |> maybe_add_opt(:visibility, params["visibility"])
            |> maybe_add_limit(params["limit"])

          Groups.list_groups(opts)
      end

    conn
    |> put_status(:ok)
    |> json(Enum.map(groups, &serialize_group/1))
  end

  # GET /api/v1/groups/:id
  def show(conn, %{"id" => id}) do
    case Groups.get_group(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "group.not_found"})

      group ->
        viewer_id = viewer_id(conn)

        conn
        |> put_status(:ok)
        |> json(serialize_group(group, viewer_id))
    end
  end

  defp viewer_id(conn) do
    case conn.assigns[:current_identity] do
      %{id: id} -> id
      _ -> nil
    end
  end

  # PATCH /api/v1/groups/:id
  def update(conn, %{"id" => id} = params) do
    identity = conn.assigns.current_identity

    case Groups.update_group(id, identity.id, params) do
      {:ok, group} ->
        conn
        |> put_status(:ok)
        |> json(serialize_group(group))

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "group.not_found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "group.forbidden"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  # DELETE /api/v1/groups/:id
  def delete(conn, %{"id" => id} = params) do
    identity = conn.assigns.current_identity
    opts = [reason: params["reason"], ip: client_ip(conn)]

    case Groups.delete_group(id, identity.id, opts) do
      {:ok, _group} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "group.deleted"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "group.not_found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "group.forbidden"})
    end
  end

  # GET /api/v1/groups/deleted — staff only: soft-deleted groups awaiting a
  # restore decision.
  def deleted(conn, params) do
    identity = conn.assigns.current_identity
    opts = maybe_add_limit([], params["limit"])

    case Groups.list_deleted_groups(identity.id, opts) do
      {:ok, groups} ->
        conn
        |> put_status(:ok)
        |> json(Enum.map(groups, &serialize_group/1))

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "group.forbidden"})
    end
  end

  # POST /api/v1/groups/:id/restore — staff only: reverse a deletion after an
  # owner's appeal. The group comes back with its non-removed content intact.
  def restore(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity

    case Groups.restore_group(id, identity.id, ip: client_ip(conn)) do
      {:ok, group} ->
        conn
        |> put_status(:ok)
        |> json(serialize_group(group))

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "group.not_found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "group.forbidden"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  # POST /api/v1/groups/:id/join
  def join(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity

    case Groups.join_group(id, identity.id) do
      # An approval/screening group returns a pending application (or, for
      # legacy rows, a pending membership); either way the client shows
      # "Requested". An open/invite join returns an approved membership.
      {:ok, %Groups.GroupApplication{}} ->
        conn
        |> put_status(:accepted)
        |> json(%{status: "pending"})

      {:ok, %Groups.GroupMember{status: :pending}} ->
        conn
        |> put_status(:accepted)
        |> json(%{status: "pending"})

      {:ok, _member} ->
        conn
        |> put_status(:ok)
        |> json(%{status: "joined"})

      {:error, :already_applied} ->
        conn
        |> put_status(:conflict)
        |> json(%{status: "pending", error: "group.already_applied"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "group.not_found"})

      {:error, :already_member} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "group.already_member"})

      {:error, :invite_required} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "group.invite_required"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  # POST /api/v1/groups/:id/leave
  def leave(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity

    case Groups.leave_group(id, identity.id) do
      {:ok, _member} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "group.left"})

      {:error, :not_member} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "group.not_member"})

      {:error, :owner_must_transfer} ->
        conn
        |> put_status(:conflict)
        |> json(%{
          error: "group.owner_must_transfer",
          detail:
            "You're the only owner. Promote another member to owner first, or delete the group."
        })
    end
  end

  # GET /api/v1/groups/:id/members
  def members(conn, %{"id" => id}) do
    members = Groups.get_members(id)

    conn
    |> put_status(:ok)
    |> json(Enum.map(members, &serialize_member/1))
  end

  # POST /api/v1/groups/:id/invite
  def invite(conn, %{"id" => id} = params) do
    identity = conn.assigns.current_identity
    invited_id = params["invited_id"]

    case Groups.invite_to_group(id, identity.id, invited_id) do
      {:ok, invite} ->
        conn
        |> put_status(:created)
        |> json(serialize_invite(invite))

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "group.not_found"})

      {:error, :not_member} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "group.not_member"})

      {:error, :invites_disabled} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "invite.disabled_by_recipient"})

      {:error, :invites_restricted} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "invite.recipient_follows_only"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  # GET /api/v1/groups/:id/invites — pending invites the admins sent.
  def list_invites(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity

    case Groups.list_pending_invites(id, identity.id) do
      {:ok, invites} ->
        conn
        |> put_status(:ok)
        |> json(Enum.map(invites, &serialize_invite/1))

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "group.forbidden"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "group.not_found"})
    end
  end

  # DELETE /api/v1/groups/:id/invites/:invite_id — admins (or the original
  # inviter) revoke an invite that hasn't been accepted yet.
  def cancel_invite(conn, %{"invite_id" => invite_id}) do
    identity = conn.assigns.current_identity

    case Groups.cancel_invite(invite_id, identity.id) do
      {:ok, _invite} ->
        send_resp(conn, :no_content, "")

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "invite.not_found"})

      {:error, :not_pending} ->
        conn |> put_status(:conflict) |> json(%{error: "invite.not_pending"})

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "invite.forbidden"})
    end
  end

  # GET /api/v1/groups/:id/applications
  def applications(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity

    # Pending applications expose applicant identities and their free-text
    # screening answers, so only group moderators/admins/owners (the same tier
    # that approves/rejects) may list them — not every authenticated user.
    if Groups.can_moderate?(id, identity.id) do
      applications = Groups.get_applications(id)

      conn
      |> put_status(:ok)
      |> json(Enum.map(applications, &serialize_application/1))
    else
      conn |> put_status(:forbidden) |> json(%{error: "group.forbidden"})
    end
  end

  # POST /api/v1/groups/:id/applications/:aid/approve
  def approve_application(conn, %{"aid" => aid}) do
    identity = conn.assigns.current_identity

    case Groups.approve_application(aid, identity.id) do
      {:ok, application} ->
        conn
        |> put_status(:ok)
        |> json(serialize_application(application))

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "application.not_found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "group.forbidden"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  # POST /api/v1/groups/:id/applications/:aid/reject
  def reject_application(conn, %{"aid" => aid}) do
    identity = conn.assigns.current_identity

    case Groups.reject_application(aid, identity.id) do
      {:ok, application} ->
        conn
        |> put_status(:ok)
        |> json(serialize_application(application))

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "application.not_found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "group.forbidden"})
    end
  end

  # PATCH /api/v1/groups/:id/members/:mid
  def update_member(conn, %{"id" => id, "mid" => mid} = params) do
    identity = conn.assigns.current_identity
    role = params["role"]

    case Groups.update_member_role(id, identity.id, mid, role) do
      {:ok, member} ->
        conn
        |> put_status(:ok)
        |> json(serialize_member(member))

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "member.not_found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "group.forbidden"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  # POST /api/v1/groups/:id/members/:mid/restrict
  #
  # Partial or timed ban. Body:
  #   restrictions: ["post", "comment", "react"]  — withhold these actions
  #   full: true                                   — full ban instead
  #   until: ISO8601                               — lapses then; omit = permanent
  #   reason: string
  #
  # An empty `restrictions` with `full: false` clears the sanction, which is
  # what DELETE on the same path does more explicitly.
  def restrict_member(conn, %{"id" => id, "mid" => mid} = params) do
    identity = conn.assigns.current_identity

    with {:ok, until} <- parse_until(params["until"]) do
      opts = [
        restrictions: params["restrictions"] || [],
        full: params["full"] == true,
        until: until,
        reason: params["reason"]
      ]

      case Groups.restrict_member(id, identity.id, mid, opts) do
        {:ok, member} ->
          conn |> put_status(:ok) |> json(serialize_member(member))

        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "member.not_found"})

        {:error, :forbidden} ->
          conn |> put_status(:forbidden) |> json(%{error: "group.forbidden"})

        {:error, :owner_must_transfer} ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: "group.owner_must_transfer"})

        {:error, {:invalid_restrictions, bad}} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "group.invalid_restrictions", invalid: bad})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "validation.failed", details: format_errors(changeset)})
      end
    else
      {:error, :bad_until} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "group.invalid_until"})
    end
  end

  # DELETE /api/v1/groups/:id/members/:mid/restrict — lift any sanction.
  def unrestrict_member(conn, %{"id" => id, "mid" => mid}) do
    identity = conn.assigns.current_identity

    case Groups.unrestrict_member(id, identity.id, mid) do
      {:ok, member} ->
        conn |> put_status(:ok) |> json(serialize_member(member))

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "member.not_found"})

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "group.forbidden"})

      {:error, _} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "validation.failed"})
    end
  end

  defp parse_until(nil), do: {:ok, nil}
  defp parse_until(""), do: {:ok, nil}

  defp parse_until(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> {:ok, DateTime.truncate(dt, :microsecond)}
      _ -> {:error, :bad_until}
    end
  end

  defp parse_until(_), do: {:error, :bad_until}

  # DELETE /api/v1/groups/:id/members/:mid
  def remove_member(conn, %{"id" => id, "mid" => mid}) do
    identity = conn.assigns.current_identity

    case Groups.ban_member(id, identity.id, mid) do
      {:ok, member} ->
        conn
        |> put_status(:ok)
        |> json(serialize_member(member))

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "member.not_found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "group.forbidden"})
    end
  end

  # GET /api/v1/groups/:id/screening
  def screening(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity

    if Groups.can_manage?(id, identity.id) do
      render_screening_config(conn, id)
    else
      conn
      |> put_status(:forbidden)
      |> json(%{error: "group.forbidden"})
    end
  end

  defp render_screening_config(conn, id) do
    case Groups.get_screening_config(id) do
      nil ->
        conn
        |> put_status(:ok)
        |> json(%{
          group_id: id,
          require_profile_image: false,
          min_account_age_days: 0,
          questions: [],
          auto_approve_rules: %{}
        })

      config ->
        conn
        |> put_status(:ok)
        |> json(serialize_screening_config(config))
    end
  end

  # PATCH /api/v1/groups/:id/screening
  def update_screening(conn, %{"id" => id} = params) do
    identity = conn.assigns.current_identity

    case Groups.update_screening_config(id, identity.id, params) do
      {:ok, config} ->
        conn
        |> put_status(:ok)
        |> json(serialize_screening_config(config))

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "group.forbidden"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  # ---------------------------------------------------------------------------
  # Serialization
  # ---------------------------------------------------------------------------

  defp serialize_group(group, viewer_id \\ nil) do
    {is_member, role} =
      case viewer_id do
        nil ->
          {false, nil}

        id ->
          case Groups.get_membership(group.id, id) do
            nil -> {false, nil}
            %{status: :approved, role: r} -> {true, r}
            %{status: status, role: r} -> {false, r |> to_string_or_nil() |> tag_status(status)}
          end
      end

    # Include the federated actor identity (id + handle) so instance
    # admins/mods can target the group's identity row with the same
    # moderation tools used for users (suspend, silence, etc.).
    group = Repo.preload(group, :identity)

    %{
      id: group.id,
      name: group.name,
      description: group.description,
      visibility: group.visibility,
      federation_mode: group.federation_mode,
      join_policy: group.join_policy,
      avatar_url: HybridsocialWeb.Helpers.Account.remote_image(group.avatar_url),
      header_url: HybridsocialWeb.Helpers.Account.remote_image(group.header_url),
      member_count: group.member_count,
      post_count: group.post_count,
      created_by: group.created_by,
      created_at: group.inserted_at,
      is_member: is_member,
      role: role,
      identity_id: group.identity_id,
      identity: serialize_actor_identity(group.identity)
    }
  end

  defp serialize_actor_identity(nil), do: nil

  defp serialize_actor_identity(%Hybridsocial.Accounts.Identity{} = identity) do
    %{
      id: identity.id,
      handle: identity.handle,
      # See PageController.invite_identity/2 — webfinger form for the UI.
      acct: HybridsocialWeb.Helpers.Account.build_acct(identity),
      display_name: identity.display_name,
      avatar_url: HybridsocialWeb.Helpers.Account.remote_image(identity.avatar_url)
    }
  end

  defp serialize_actor_identity(_), do: nil

  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(v) when is_atom(v), do: Atom.to_string(v)
  defp to_string_or_nil(v), do: v

  # If membership exists but isn't `:active` (pending / banned), keep
  # the role string but suffix the status so the UI can show the right
  # state. The frontend currently only needs is_member; this is just
  # forward-friendly.
  defp tag_status(role, status), do: "#{role || "member"}:#{status}"

  # GET /api/v1/groups/:id/reports — the group's own moderation queue.
  # Moderator-tier; the check lives in Moderation.list_group_reports/3.
  def reports(conn, %{"id" => id} = params) do
    identity = conn.assigns.current_identity
    opts = [status: params["status"], limit: clamp_limit(params["limit"])]

    case Hybridsocial.Moderation.list_group_reports(id, identity.id, opts) do
      {:ok, reports} ->
        conn |> put_status(:ok) |> json(Enum.map(reports, &serialize_group_report/1))

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "group.forbidden"})
    end
  end

  defp serialize_group_report(r) do
    %{
      id: r.id,
      category: r.category,
      description: r.description,
      status: r.status,
      tier: r.tier,
      target_type: r.target_type,
      target_id: r.target_id,
      # Surfaced so a group mod can see at a glance that a report has already
      # gone to instance staff — either escalated, or pulled by category.
      escalated_at: r.escalated_at,
      created_at: r.inserted_at,
      reporter: brief_account(r.reporter),
      reported: brief_account(r.reported)
    }
  end

  defp brief_account(nil), do: nil

  defp brief_account(identity) do
    %{
      id: identity.id,
      handle: identity.handle,
      display_name: identity.display_name,
      avatar_url: HybridsocialWeb.Helpers.Account.remote_image(identity.avatar_url)
    }
  end

  defp now_utc, do: DateTime.utc_now()

  defp serialize_member(member) do
    identity = Hybridsocial.Accounts.get_identity(member.identity_id)

    %{
      id: member.id,
      group_id: member.group_id,
      identity_id: member.identity_id,
      role: member.role,
      status: member.status,
      # Effective values, so the client shows what's actually in force rather
      # than a row that hasn't been swept yet: a lapsed sanction reads as
      # cleared here even before the expiry worker tidies it.
      effective_status: Hybridsocial.Groups.GroupMember.effective_status(member, now_utc()),
      restrictions: Hybridsocial.Groups.GroupMember.effective_restrictions(member, now_utc()),
      restricted_until: member.restricted_until,
      restriction_reason: member.restriction_reason,
      created_at: member.inserted_at,
      account:
        if(identity,
          do: %{
            id: identity.id,
            handle: identity.handle,
            acct: HybridsocialWeb.Helpers.Account.build_acct(identity),
            display_name: identity.display_name,
            avatar_url: HybridsocialWeb.Helpers.Account.remote_image(identity.avatar_url)
          }
        )
    }
  end

  defp serialize_application(application) do
    identity =
      case application.identity do
        %Ecto.Association.NotLoaded{} -> nil
        loaded -> loaded
      end

    %{
      id: application.id,
      group_id: application.group_id,
      identity_id: application.identity_id,
      answers: application.answers,
      status: application.status,
      reviewed_by: application.reviewed_by,
      created_at: application.created_at,
      reviewed_at: application.reviewed_at,
      account:
        if(identity,
          do: %{
            id: identity.id,
            handle: identity.handle,
            acct: HybridsocialWeb.Helpers.Account.build_acct(identity),
            display_name: identity.display_name,
            avatar_url: HybridsocialWeb.Helpers.Account.remote_image(identity.avatar_url)
          }
        )
    }
  end

  defp serialize_invite(invite) do
    %{
      id: invite.id,
      group_id: invite.group_id,
      invited_by: invite.invited_by,
      invited_id: invite.invited_id,
      invited: invite_identity(invite, :invited),
      inviter: invite_identity(invite, :inviter),
      status: invite.status,
      created_at: invite.inserted_at
    }
  end

  defp invite_identity(invite, assoc) do
    case Map.get(invite, assoc) do
      %Hybridsocial.Accounts.Identity{} = identity -> serialize_actor_identity(identity)
      _ -> nil
    end
  end

  defp serialize_screening_config(config) do
    %{
      group_id: config.group_id,
      require_profile_image: config.require_profile_image,
      min_account_age_days: config.min_account_age_days,
      questions: config.questions,
      auto_approve_rules: config.auto_approve_rules
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp maybe_add_limit(opts, nil), do: opts
  defp maybe_add_limit(opts, val), do: Keyword.put(opts, :limit, clamp_limit(val))

  defp client_ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()
end
