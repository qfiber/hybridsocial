defmodule Hybridsocial.Instance do
  @moduledoc "Instance info and NodeInfo."
  import Ecto.Query
  alias Hybridsocial.Repo
  alias Hybridsocial.Config

  @version "0.1.0"

  def info do
    base_url = HybridsocialWeb.Endpoint.url()

    %{
      uri: URI.parse(base_url).host || "localhost",
      title: Config.get("instance_name", "HybridSocial"),
      short_description: Config.get("instance_description", ""),
      description: Config.get("instance_description", ""),
      email: Config.get("contact_email", ""),
      version: "#{@version} (compatible; Mastodon 4.0)",
      urls: %{
        streaming_api: String.replace(base_url, "http", "ws") <> "/socket"
      },
      stats: stats(),
      thumbnail: Config.get("instance_thumbnail", nil),
      languages: ["en"],
      registrations: Config.get("registration_mode", "open") != "closed",
      approval_required: Config.get("registration_mode", "open") == "approval",
      invites_enabled: Config.get("registration_mode", "open") != "closed",
      configuration: %{
        statuses: %{
          max_characters: Config.get("max_post_length_free", 5000),
          max_media_attachments: Config.get("max_media_per_post", 4),
          characters_reserved_per_url: 23
        },
        media_attachments: %{
          supported_mime_types: [
            "image/jpeg",
            "image/png",
            "image/gif",
            "image/webp",
            "video/mp4",
            "video/webm"
          ],
          image_size_limit: Config.get("max_image_size_mb", 10) * 1_048_576,
          video_size_limit: Config.get("max_video_size_mb", 100) * 1_048_576,
          video_frame_rate_limit: 60,
          video_matrix_limit: 8_294_400
        },
        polls: %{
          max_options: 4,
          max_characters_per_option: 100,
          min_expiration: 300,
          max_expiration: 2_629_746
        },
        accounts: %{
          max_featured_tags: 10
        }
      },
      contact_account: nil,
      rules: rules()
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
      status_count: post_count(),
      domain_count: domain_count()
    }
  end

  def rules do
    try do
      from(r in "instance_settings",
        where: r.key == "instance_rules",
        select: r.value
      )
      |> Repo.one()
      |> case do
        %{"value" => rules} when is_list(rules) ->
          rules
          |> Enum.with_index(1)
          |> Enum.map(fn {text, id} ->
            %{id: to_string(id), text: text, hint: ""}
          end)

        _ ->
          []
      end
    rescue
      _ -> []
    end
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
