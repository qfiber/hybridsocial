defmodule Hybridsocial.Badges do
  @moduledoc """
  Computes badges for identities based on their roles.

  Instance badges (admin/moderator/owner) respect the user's show_badge preference.
  Group/Page badges (admin/moderator/owner) are always visible within that context.
  """

  import Ecto.Query
  alias Hybridsocial.Repo
  alias Hybridsocial.Auth.RBAC

  @doc """
  Get instance-level badges for an identity.
  Returns a list of badge maps, respecting show_badge preference.
  """
  def instance_badges(identity) do
    if identity.show_badge == false do
      []
    else
      roles = RBAC.get_roles(identity.id)
      badges = []

      badges =
        cond do
          "owner" in roles -> [%{type: "owner", label: "Owner"} | badges]
          identity.is_admin -> [%{type: "admin", label: "Admin"} | badges]
          true -> badges
        end

      badges =
        if "moderator" in roles do
          [%{type: "moderator", label: "Mod"} | badges]
        else
          badges
        end

      badges =
        if identity.is_bot do
          [%{type: "bot", label: "Bot"} | badges]
        else
          badges
        end

      # Verification tier badge (L1+)
      badges =
        case identity.verification_tier do
          "verified_starter" -> [%{type: "verified_l1", label: "Verified"} | badges]
          "verified_creator" -> [%{type: "verified_l2", label: "Verified"} | badges]
          "verified_pro" -> [%{type: "verified_l3", label: "Verified Pro"} | badges]
          _ -> badges
        end

      Enum.reverse(badges)
    end
  end

  @doc """
  Get the badge for an identity within a group context.
  Always visible — cannot be hidden.
  """
  def group_badge(identity_id, group_id) do
    case Repo.one(
           from(gm in "group_members",
             where:
               gm.identity_id == type(^identity_id, Ecto.UUID) and
                 gm.group_id == type(^group_id, Ecto.UUID) and
                 gm.status == "approved",
             select: gm.role
           )
         ) do
      "owner" -> %{type: "owner", label: "Owner"}
      "admin" -> %{type: "admin", label: "Admin"}
      "moderator" -> %{type: "moderator", label: "Mod"}
      _ -> nil
    end
  end

  @doc """
  Get the badge for an identity within a page/organization context.
  Always visible — cannot be hidden.
  """
  def page_badge(identity_id, organization_id) do
    case Repo.one(
           from(or_ in "organization_roles",
             where:
               or_.identity_id == type(^identity_id, Ecto.UUID) and
                 or_.organization_id == type(^organization_id, Ecto.UUID),
             select: or_.role
           )
         ) do
      "admin" -> %{type: "admin", label: "Admin"}
      "moderator" -> %{type: "moderator", label: "Mod"}
      "editor" -> %{type: "editor", label: "Editor"}
      _ -> nil
    end
  end

  @doc """
  Compute all badges for a serialized account on a post.
  Takes identity and optional group_id/page_id from the post context.
  """
  def badges_for_post(identity, opts \\ []) do
    group_id = Keyword.get(opts, :group_id)
    page_id = Keyword.get(opts, :page_id)

    instance = instance_badges(identity)

    context =
      cond do
        group_id ->
          case group_badge(identity.id, group_id) do
            nil -> []
            badge -> [badge]
          end

        page_id ->
          case page_badge(identity.id, page_id) do
            nil -> []
            badge -> [badge]
          end

        true ->
          []
      end

    instance ++ context
  end
end
