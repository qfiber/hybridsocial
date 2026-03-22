defmodule Hybridsocial.Instance do
  @moduledoc "Instance info and NodeInfo."
  import Ecto.Query
  alias Hybridsocial.Repo
  alias Hybridsocial.Config

  @version "0.1.0"

  def info do
    %{
      name: Config.get("instance_name", "HybridSocial"),
      description: Config.get("instance_description", ""),
      version: @version,
      stats: stats(),
      registrations: Config.get("registration_mode", "open") != "closed",
      registration_mode: Config.get("registration_mode", "open"),
      contact_email: Config.get("contact_email", "")
    }
  end

  def nodeinfo do
    %{
      version: "2.0",
      software: %{name: "hybridsocial", version: @version},
      protocols: ["activitypub"],
      usage: %{
        users: %{total: user_count(), activeMonth: active_users_count(30)},
        localPosts: post_count()
      },
      openRegistrations: Config.get("registration_mode", "open") != "closed"
    }
  end

  def stats do
    %{
      user_count: user_count(),
      post_count: post_count(),
      domain_count: domain_count()
    }
  end

  defp user_count do
    from(i in "identities",
      where: i.type == "user" and is_nil(i.deleted_at),
      select: count(i.id)
    )
    |> Repo.one() || 0
  end

  defp post_count do
    from(p in "posts", where: is_nil(p.deleted_at), select: count(p.id))
    |> Repo.one() || 0
  end

  defp domain_count do
    from(r in "remote_actors", select: count(fragment("DISTINCT ?", r.domain)))
    |> Repo.one() || 0
  end

  defp active_users_count(days) do
    cutoff = DateTime.add(DateTime.utc_now(), -days * 86400, :second)

    from(u in "users", where: u.last_login_at > ^cutoff, select: count(u.identity_id))
    |> Repo.one() || 0
  end
end
