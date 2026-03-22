defmodule Hybridsocial.Groups do
  @moduledoc """
  The Groups context. Manages groups, memberships, screening, applications, and invites.
  """
  import Ecto.Query

  alias Hybridsocial.Repo
  alias Hybridsocial.Groups.{Group, GroupMember, GroupScreeningConfig, GroupApplication, GroupInvite}
  alias Hybridsocial.Accounts

  @default_page_size 20

  # ---------------------------------------------------------------------------
  # Group CRUD
  # ---------------------------------------------------------------------------

  def create_group(identity_id, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:group, fn _ ->
      %Group{}
      |> Group.create_changeset(Map.put(attrs, "created_by", identity_id))
    end)
    |> Ecto.Multi.insert(:owner_member, fn %{group: group} ->
      %GroupMember{}
      |> GroupMember.changeset(%{
        group_id: group.id,
        identity_id: identity_id,
        role: :owner,
        status: :approved
      })
    end)
    |> Ecto.Multi.update(:update_count, fn %{group: group} ->
      group
      |> Ecto.Changeset.change(member_count: 1)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{group: _group, update_count: group_updated}} ->
        {:ok, group_updated}

      {:error, :group, changeset, _} ->
        {:error, changeset}

      {:error, :owner_member, changeset, _} ->
        {:error, changeset}
    end
  end

  def update_group(group_id, identity_id, attrs) do
    with {:ok, group} <- get_existing_group(group_id),
         {:ok, _role} <- require_role(group_id, identity_id, [:admin, :owner]) do
      group
      |> Group.update_changeset(attrs)
      |> Repo.update()
    end
  end

  def delete_group(group_id, identity_id) do
    with {:ok, group} <- get_existing_group(group_id),
         {:ok, _role} <- require_role(group_id, identity_id, [:owner]) do
      group
      |> Group.soft_delete_changeset()
      |> Repo.update()
    end
  end

  def get_group(id) do
    Group
    |> where([g], is_nil(g.deleted_at))
    |> Repo.get(id)
  end

  def get_group!(id) do
    Group
    |> where([g], is_nil(g.deleted_at))
    |> Repo.get!(id)
  end

  def list_groups(opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_page_size)
    cursor = Keyword.get(opts, :cursor)
    visibility = Keyword.get(opts, :visibility)

    query =
      Group
      |> where([g], is_nil(g.deleted_at))
      |> order_by([g], desc: g.inserted_at)
      |> limit(^limit)

    query =
      if visibility do
        where(query, [g], g.visibility == ^visibility)
      else
        query
      end

    query =
      if cursor do
        where(query, [g], g.inserted_at < ^cursor)
      else
        query
      end

    Repo.all(query)
  end

  def search_groups(query_string) do
    pattern = "%#{query_string}%"

    Group
    |> where([g], is_nil(g.deleted_at))
    |> where([g], ilike(g.name, ^pattern) or ilike(g.description, ^pattern))
    |> order_by([g], desc: g.inserted_at)
    |> limit(@default_page_size)
    |> Repo.all()
  end

  # ---------------------------------------------------------------------------
  # Membership
  # ---------------------------------------------------------------------------

  def join_group(group_id, identity_id) do
    with {:ok, group} <- get_existing_group(group_id),
         nil <- get_member(group_id, identity_id) do
      case group.join_policy do
        :open ->
          insert_member(group_id, identity_id, :member, :approved)

        :screening ->
          case check_auto_approval(group_id, identity_id, %{}) do
            :approved ->
              insert_member(group_id, identity_id, :member, :approved)

            :pending ->
              insert_member(group_id, identity_id, :member, :pending)
          end

        :approval ->
          insert_member(group_id, identity_id, :member, :pending)

        :invite_only ->
          case get_pending_invite(group_id, identity_id) do
            nil ->
              {:error, :invite_required}

            invite ->
              invite
              |> GroupInvite.changeset(%{status: "accepted"})
              |> Repo.update()

              insert_member(group_id, identity_id, :member, :approved)
          end
      end
    else
      %GroupMember{} -> {:error, :already_member}
      {:error, reason} -> {:error, reason}
    end
  end

  def leave_group(group_id, identity_id) do
    case get_member(group_id, identity_id) do
      nil ->
        {:error, :not_member}

      member ->
        Repo.delete(member)
        update_member_count(group_id, -1)
        {:ok, member}
    end
  end

  def get_members(group_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_page_size)
    status = Keyword.get(opts, :status, :approved)

    GroupMember
    |> where([m], m.group_id == ^group_id and m.status == ^status)
    |> order_by([m], asc: m.inserted_at)
    |> limit(^limit)
    |> preload(:identity)
    |> Repo.all()
  end

  def update_member_role(group_id, admin_id, member_id, role) do
    with {:ok, _role} <- require_role(group_id, admin_id, [:admin, :owner]),
         member when not is_nil(member) <- get_member_by_id(member_id, group_id) do
      member
      |> GroupMember.changeset(%{role: role})
      |> Repo.update()
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def ban_member(group_id, admin_id, member_id) do
    with {:ok, _role} <- require_role(group_id, admin_id, [:admin, :owner]),
         member when not is_nil(member) <- get_member_by_id(member_id, group_id) do
      member
      |> GroupMember.changeset(%{status: :banned})
      |> Repo.update()
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def member?(group_id, identity_id) do
    GroupMember
    |> where([m], m.group_id == ^group_id and m.identity_id == ^identity_id and m.status == :approved)
    |> Repo.exists?()
  end

  def member_role(group_id, identity_id) do
    GroupMember
    |> where([m], m.group_id == ^group_id and m.identity_id == ^identity_id and m.status == :approved)
    |> select([m], m.role)
    |> Repo.one()
  end

  # ---------------------------------------------------------------------------
  # Screening
  # ---------------------------------------------------------------------------

  def get_screening_config(group_id) do
    Repo.get(GroupScreeningConfig, group_id)
  end

  def update_screening_config(group_id, admin_id, attrs) do
    with {:ok, _role} <- require_role(group_id, admin_id, [:admin, :owner]) do
      case get_screening_config(group_id) do
        nil ->
          %GroupScreeningConfig{}
          |> GroupScreeningConfig.changeset(Map.put(attrs, "group_id", group_id))
          |> Repo.insert()

        config ->
          config
          |> GroupScreeningConfig.changeset(attrs)
          |> Repo.update()
      end
    end
  end

  def check_auto_approval(group_id, identity_id, _answers) do
    config = get_screening_config(group_id)

    cond do
      is_nil(config) ->
        :approved

      config.require_profile_image ->
        identity = Accounts.get_identity(identity_id)

        if identity && identity.avatar_url do
          check_account_age(config, identity)
        else
          :pending
        end

      config.min_account_age_days > 0 ->
        identity = Accounts.get_identity(identity_id)
        check_account_age(config, identity)

      true ->
        :approved
    end
  end

  # ---------------------------------------------------------------------------
  # Applications
  # ---------------------------------------------------------------------------

  def apply_to_group(group_id, identity_id, answers) do
    with {:ok, _group} <- get_existing_group(group_id) do
      %GroupApplication{}
      |> GroupApplication.changeset(%{
        group_id: group_id,
        identity_id: identity_id,
        answers: answers
      })
      |> Repo.insert()
    end
  end

  def approve_application(application_id, admin_id) do
    with {:ok, application} <- get_application(application_id),
         {:ok, _role} <- require_role(application.group_id, admin_id, [:admin, :owner]) do
      Ecto.Multi.new()
      |> Ecto.Multi.update(:application, fn _ ->
        GroupApplication.review_changeset(application, %{
          status: :approved,
          reviewed_by: admin_id
        })
      end)
      |> Ecto.Multi.insert(:member, fn _ ->
        %GroupMember{}
        |> GroupMember.changeset(%{
          group_id: application.group_id,
          identity_id: application.identity_id,
          role: :member,
          status: :approved
        })
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{application: application, member: _member}} ->
          update_member_count(application.group_id, 1)
          {:ok, application}

        {:error, :application, changeset, _} ->
          {:error, changeset}

        {:error, :member, changeset, _} ->
          {:error, changeset}
      end
    end
  end

  def reject_application(application_id, admin_id) do
    with {:ok, application} <- get_application(application_id),
         {:ok, _role} <- require_role(application.group_id, admin_id, [:admin, :owner]) do
      application
      |> GroupApplication.review_changeset(%{
        status: :rejected,
        reviewed_by: admin_id
      })
      |> Repo.update()
    end
  end

  def get_applications(group_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_page_size)
    status = Keyword.get(opts, :status, :pending)

    GroupApplication
    |> where([a], a.group_id == ^group_id and a.status == ^status)
    |> order_by([a], asc: a.created_at)
    |> limit(^limit)
    |> preload(:identity)
    |> Repo.all()
  end

  # ---------------------------------------------------------------------------
  # Invites
  # ---------------------------------------------------------------------------

  def invite_to_group(group_id, inviter_id, invited_id) do
    with {:ok, _group} <- get_existing_group(group_id),
         true <- member?(group_id, inviter_id) || {:error, :not_member} do
      %GroupInvite{}
      |> GroupInvite.changeset(%{
        group_id: group_id,
        invited_by: inviter_id,
        invited_id: invited_id
      })
      |> Repo.insert()
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def accept_invite(invite_id, identity_id) do
    with {:ok, invite} <- get_invite(invite_id),
         true <- invite.invited_id == identity_id || {:error, :forbidden} do
      Ecto.Multi.new()
      |> Ecto.Multi.update(:invite, fn _ ->
        invite
        |> GroupInvite.changeset(%{status: "accepted"})
      end)
      |> Ecto.Multi.insert(:member, fn _ ->
        %GroupMember{}
        |> GroupMember.changeset(%{
          group_id: invite.group_id,
          identity_id: identity_id,
          role: :member,
          status: :approved
        })
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{invite: invite, member: _member}} ->
          update_member_count(invite.group_id, 1)
          {:ok, invite}

        {:error, :invite, changeset, _} ->
          {:error, changeset}

        {:error, :member, changeset, _} ->
          {:error, changeset}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def decline_invite(invite_id, identity_id) do
    with {:ok, invite} <- get_invite(invite_id),
         true <- invite.invited_id == identity_id || {:error, :forbidden} do
      invite
      |> GroupInvite.changeset(%{status: "declined"})
      |> Repo.update()
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def get_invites(identity_id) do
    GroupInvite
    |> where([i], i.invited_id == ^identity_id and i.status == "pending")
    |> order_by([i], desc: i.inserted_at)
    |> preload([:group, :inviter])
    |> Repo.all()
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp get_existing_group(group_id) do
    case get_group(group_id) do
      nil -> {:error, :not_found}
      group -> {:ok, group}
    end
  end

  defp get_member(group_id, identity_id) do
    GroupMember
    |> where([m], m.group_id == ^group_id and m.identity_id == ^identity_id)
    |> Repo.one()
  end

  defp get_member_by_id(member_id, group_id) do
    GroupMember
    |> where([m], m.id == ^member_id and m.group_id == ^group_id)
    |> Repo.one()
  end

  defp insert_member(group_id, identity_id, role, status) do
    result =
      %GroupMember{}
      |> GroupMember.changeset(%{
        group_id: group_id,
        identity_id: identity_id,
        role: role,
        status: status
      })
      |> Repo.insert()

    case result do
      {:ok, member} ->
        if status == :approved, do: update_member_count(group_id, 1)
        {:ok, member}

      error ->
        error
    end
  end

  defp update_member_count(group_id, delta) do
    Group
    |> where([g], g.id == ^group_id)
    |> Repo.update_all(inc: [member_count: delta])
  end

  defp require_role(group_id, identity_id, allowed_roles) do
    case member_role(group_id, identity_id) do
      nil ->
        {:error, :forbidden}

      role ->
        if role in allowed_roles, do: {:ok, role}, else: {:error, :forbidden}
    end
  end

  defp get_application(application_id) do
    case Repo.get(GroupApplication, application_id) do
      nil -> {:error, :not_found}
      application -> {:ok, application}
    end
  end

  defp get_invite(invite_id) do
    case Repo.get(GroupInvite, invite_id) do
      nil -> {:error, :not_found}
      invite -> {:ok, invite}
    end
  end

  defp get_pending_invite(group_id, identity_id) do
    GroupInvite
    |> where([i], i.group_id == ^group_id and i.invited_id == ^identity_id and i.status == "pending")
    |> Repo.one()
  end

  defp check_account_age(config, identity) do
    if config.min_account_age_days > 0 && identity do
      account_age_days = DateTime.diff(DateTime.utc_now(), identity.inserted_at, :day)

      if account_age_days >= config.min_account_age_days do
        :approved
      else
        :pending
      end
    else
      :approved
    end
  end
end
