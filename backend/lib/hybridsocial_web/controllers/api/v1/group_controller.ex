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
      if params["q"] do
        Groups.search_groups(params["q"])
      else
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
  def delete(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity

    case Groups.delete_group(id, identity.id) do
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

  # POST /api/v1/groups/:id/join
  def join(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity

    case Groups.join_group(id, identity.id) do
      {:ok, member} ->
        conn
        |> put_status(:ok)
        |> json(serialize_member(member))

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

    cond do
      not Groups.can_manage?(id, identity.id) ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "group.forbidden"})

      true ->
        render_screening_config(conn, id)
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
      avatar_url: group.avatar_url,
      header_url: group.header_url,
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
      avatar_url: identity.avatar_url
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

  defp serialize_member(member) do
    identity = Hybridsocial.Accounts.get_identity(member.identity_id)

    %{
      id: member.id,
      group_id: member.group_id,
      identity_id: member.identity_id,
      role: member.role,
      status: member.status,
      created_at: member.inserted_at,
      account:
        if(identity,
          do: %{
            id: identity.id,
            handle: identity.handle,
            acct: HybridsocialWeb.Helpers.Account.build_acct(identity),
            display_name: identity.display_name,
            avatar_url: identity.avatar_url
          }
        )
    }
  end

  defp serialize_application(application) do
    %{
      id: application.id,
      group_id: application.group_id,
      identity_id: application.identity_id,
      answers: application.answers,
      status: application.status,
      reviewed_by: application.reviewed_by,
      created_at: application.created_at,
      reviewed_at: application.reviewed_at
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
end
