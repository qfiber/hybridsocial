defmodule HybridsocialWeb.Api.V1.GroupController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Groups

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
        conn
        |> put_status(:ok)
        |> json(serialize_group(group))
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

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  # GET /api/v1/groups/:id/applications
  def applications(conn, %{"id" => id}) do
    applications = Groups.get_applications(id)

    conn
    |> put_status(:ok)
    |> json(Enum.map(applications, &serialize_application/1))
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

  defp serialize_group(group) do
    %{
      id: group.id,
      name: group.name,
      description: group.description,
      visibility: group.visibility,
      join_policy: group.join_policy,
      avatar_url: group.avatar_url,
      header_url: group.header_url,
      member_count: group.member_count,
      post_count: group.post_count,
      created_by: group.created_by,
      created_at: group.inserted_at
    }
  end

  defp serialize_member(member) do
    identity = Hybridsocial.Accounts.get_identity(member.identity_id)

    %{
      id: member.id,
      group_id: member.group_id,
      identity_id: member.identity_id,
      role: member.role,
      status: member.status,
      created_at: member.inserted_at,
      account: if(identity, do: %{
        id: identity.id,
        handle: identity.handle,
        display_name: identity.display_name,
        avatar_url: identity.avatar_url
      })
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
      status: invite.status,
      created_at: invite.inserted_at
    }
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
  defp maybe_add_limit(opts, val), do: Keyword.put(opts, :limit, String.to_integer(val))
end
