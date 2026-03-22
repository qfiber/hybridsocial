defmodule Hybridsocial.Instance do
  @moduledoc "Instance info — compatible with Mastodon, Pleroma, and Misskey client APIs."
  import Ecto.Query
  alias Hybridsocial.Repo
  alias Hybridsocial.Config

  @version "0.1.0"

  @features [
    "mastodon_api",
    "mastodon_api_streaming",
    "pleroma_api",
    "pleroma_emoji_reactions",
    "pleroma_custom_emoji_reactions",
    "pleroma_chat_messages",
    "pleroma_explicit_addressing",
    "shareable_emoji_packs",
    "polls",
    "quote_posting",
    "editing",
    "relay",
    "safe_dm_mentions",
    "multifetch",
    "v2_suggestions",
    "profile_directory",
    "exposable_reactions",
    "events"
  ]

  def info do
    base_url = HybridsocialWeb.Endpoint.url()
    host = URI.parse(base_url).host || "localhost"
    upload_limit = Config.get("max_upload_payload_bytes", 100_000_000)
    max_chars = Config.get("max_post_length_free", 5000)
    max_media = Config.get("max_media_per_post", 4)
    image_limit = Config.get("max_image_size_mb", 10) * 1_048_576
    video_limit = Config.get("max_video_size_mb", 100) * 1_048_576
    reg_mode = Config.get("registration_mode", "open")

    %{
      # === Shared (Mastodon + Pleroma) ===
      uri: host,
      title: Config.get("instance_name", "HybridSocial"),
      short_description:
        Config.get("instance_short_description", Config.get("instance_description", "")),
      description: Config.get("instance_description", ""),
      email: Config.get("contact_email", ""),
      version: "2.7.2 (compatible; Pleroma 2.6.50; HybridSocial #{@version})",
      urls: %{
        streaming_api: String.replace(base_url, "http", "ws") <> "/socket"
      },
      stats: stats(),
      thumbnail: Config.get("instance_thumbnail", nil),
      languages: languages(),
      registrations: reg_mode != "closed",
      approval_required: reg_mode == "approval",
      invites_enabled: reg_mode != "closed",
      configuration: %{
        statuses: %{
          max_characters: max_chars,
          max_media_attachments: max_media,
          characters_reserved_per_url: Config.get("characters_reserved_per_url", 23)
        },
        media_attachments: %{
          supported_mime_types: supported_mime_types(),
          image_size_limit: image_limit,
          video_size_limit: video_limit,
          video_frame_rate_limit: Config.get("video_frame_rate_limit", 120),
          video_matrix_limit: Config.get("video_matrix_limit", 8_294_400),
          image_matrix_limit: Config.get("image_matrix_limit", 33_177_600)
        },
        polls: %{
          max_options: Config.get("max_poll_options", 4),
          max_characters_per_option: Config.get("max_poll_option_chars", 200),
          min_expiration: Config.get("min_poll_expiration", 300),
          max_expiration: Config.get("max_poll_expiration", 2_629_746)
        },
        accounts: %{
          max_featured_tags: Config.get("max_featured_tags", 10)
        }
      },
      contact_account: contact_account(),
      rules: rules(),

      # === Mastodon-specific ===
      # (Mastodon clients look for these)

      # === Pleroma-specific ===
      max_toot_chars: max_chars,
      max_media_attachments: max_media,
      description_limit: max_chars,
      upload_limit: upload_limit,
      avatar_upload_limit: Config.get("max_avatar_size", 2_000_000),
      background_upload_limit: Config.get("max_background_size", 4_000_000),
      banner_upload_limit: Config.get("max_banner_size", 4_000_000),
      background_image: Config.get("instance_background_image", nil),
      poll_limits: %{
        max_options: Config.get("max_poll_options", 4),
        max_option_chars: Config.get("max_poll_option_chars", 200),
        min_expiration: Config.get("min_poll_expiration", 300),
        max_expiration: Config.get("max_poll_expiration", 2_629_746)
      },
      pleroma: %{
        metadata: %{
          account_activation_required: Config.get("require_email_confirmation", true),
          birthday_min_age: 0,
          birthday_required: false,
          features: @features,
          federation: %{
            enabled: Config.get("federation_enabled", true),
            exclusions: false,
            mrf_policies: ["SimplePolicy"],
            mrf_simple: federation_policies()
          },
          fields_limits: %{
            max_fields: Config.get("max_profile_fields", 5),
            max_remote_fields: 20,
            name_length: Config.get("max_field_name_length", 512),
            value_length: Config.get("max_field_value_length", 2048)
          },
          markup: %{
            allow_headings: true,
            allow_inline_images: true,
            allow_tables: false
          },
          post_formats: ["text/plain", "text/markdown"],
          privileged_staff: true,
          restrict_unauthenticated: %{
            activities: %{local: false, remote: true},
            profiles: %{local: false, remote: true},
            timelines: %{local: false, federated: true}
          }
        },
        stats: %{
          mau: active_users_count(30)
        },
        vapid_public_key: Config.get("vapid_public_key", nil)
      }
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

  defp languages do
    case Config.get("instance_languages", nil) do
      nil -> ["en"]
      langs when is_list(langs) -> langs
      langs when is_binary(langs) -> String.split(langs, ",") |> Enum.map(&String.trim/1)
      _ -> ["en"]
    end
  end

  defp supported_mime_types do
    [
      "image/jpeg",
      "image/png",
      "image/gif",
      "image/webp",
      "image/avif",
      "video/mp4",
      "video/webm",
      "video/quicktime",
      "audio/mpeg",
      "audio/ogg",
      "audio/wav",
      "audio/flac",
      "audio/aac"
    ]
  end

  defp contact_account do
    case Config.get("contact_account_handle", nil) do
      nil ->
        nil

      handle ->
        case Repo.one(
               from(i in "identities",
                 where: i.handle == ^handle and is_nil(i.deleted_at),
                 select: %{
                   id: i.id,
                   handle: i.handle,
                   display_name: i.display_name,
                   avatar_url: i.avatar_url,
                   header_url: i.header_url,
                   bio: i.bio,
                   is_locked: i.is_locked,
                   is_bot: i.is_bot,
                   inserted_at: i.inserted_at
                 }
               )
             ) do
          nil ->
            nil

          account ->
            base_url = HybridsocialWeb.Endpoint.url()

            %{
              id: account.id,
              username: account.handle,
              acct: account.handle,
              display_name: account.display_name || account.handle,
              locked: account.is_locked || false,
              bot: account.is_bot || false,
              created_at: account.inserted_at,
              note: account.bio || "",
              url: "#{base_url}/@#{account.handle}",
              uri: "#{base_url}/actors/#{account.id}",
              avatar: account.avatar_url || "",
              avatar_static: account.avatar_url || "",
              header: account.header_url || "",
              header_static: account.header_url || "",
              followers_count: 0,
              following_count: 0,
              statuses_count: 0,
              emojis: [],
              fields: []
            }
        end
    end
  end

  defp federation_policies do
    try do
      policies =
        from(p in "instance_policies",
          select: %{domain: p.domain, policy: p.policy}
        )
        |> Repo.all()

      reject = policies |> Enum.filter(&(&1.policy == "suspend")) |> Enum.map(& &1.domain)
      media_nsfw = policies |> Enum.filter(&(&1.policy == "force_nsfw")) |> Enum.map(& &1.domain)

      media_removal =
        policies |> Enum.filter(&(&1.policy == "block_media")) |> Enum.map(& &1.domain)

      federated_timeline_removal =
        policies |> Enum.filter(&(&1.policy == "silence")) |> Enum.map(& &1.domain)

      %{
        accept: [],
        reject: reject,
        media_nsfw: media_nsfw,
        media_removal: media_removal,
        federated_timeline_removal: federated_timeline_removal,
        followers_only: [],
        report_removal: [],
        reject_deletes: [],
        avatar_removal: [],
        banner_removal: []
      }
    rescue
      _ ->
        %{
          accept: [],
          reject: [],
          media_nsfw: [],
          media_removal: [],
          federated_timeline_removal: []
        }
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
