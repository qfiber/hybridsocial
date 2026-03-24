defmodule HybridsocialWeb.Api.V1.CustomEmojiController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Content.Emojis

  # GET /api/v1/custom_emojis
  def index(conn, params) do
    opts =
      case Map.get(params, "category") do
        nil -> []
        category -> [category: category]
      end

    emojis = Emojis.list_emojis(opts)

    conn
    |> put_status(:ok)
    |> json(Enum.map(emojis, &serialize_emoji/1))
  end

  defp serialize_emoji(emoji) do
    %{
      id: emoji.id,
      shortcode: emoji.shortcode,
      image_url: emoji.image_url,
      category: emoji.category,
      enabled: emoji.enabled,
      premium: emoji.premium
    }
  end
end
