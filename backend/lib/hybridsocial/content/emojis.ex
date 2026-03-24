defmodule Hybridsocial.Content.Emojis do
  @moduledoc """
  Context module for managing custom emojis.
  """
  import Ecto.Query
  alias Hybridsocial.Repo
  alias Hybridsocial.Content.CustomEmoji

  @doc """
  Lists all enabled emojis, optionally filtered by category.
  """
  def list_emojis(opts \\ []) do
    category = Keyword.get(opts, :category)

    query =
      CustomEmoji
      |> where([e], e.enabled == true)
      |> order_by([e], asc: e.shortcode)

    query =
      if category do
        where(query, [e], e.category == ^category)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Gets a single emoji by ID.
  """
  def get_emoji(id) do
    Repo.get(CustomEmoji, id)
  end

  @doc """
  Gets a single emoji by shortcode.
  """
  def get_emoji_by_shortcode(shortcode) do
    Repo.get_by(CustomEmoji, shortcode: shortcode)
  end

  @doc """
  Creates a custom emoji (caller checks admin permission).
  """
  def create_emoji(attrs) do
    %CustomEmoji{}
    |> CustomEmoji.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a custom emoji.
  """
  def update_emoji(id, attrs) do
    case get_emoji(id) do
      nil ->
        {:error, :not_found}

      emoji ->
        emoji
        |> CustomEmoji.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Deletes a custom emoji.
  """
  def delete_emoji(id) do
    case get_emoji(id) do
      nil ->
        {:error, :not_found}

      emoji ->
        Repo.delete(emoji)
    end
  end

  @doc """
  Returns the set of premium emoji shortcodes used in text.
  """
  def premium_shortcodes_in_text(text) when is_binary(text) do
    shortcodes =
      Regex.scan(~r/:([a-zA-Z0-9_]+):/, text, capture: :all_but_first)
      |> List.flatten()
      |> Enum.uniq()

    if shortcodes == [] do
      []
    else
      CustomEmoji
      |> where([e], e.shortcode in ^shortcodes and e.premium == true and e.enabled == true)
      |> select([e], e.shortcode)
      |> Repo.all()
    end
  end

  def premium_shortcodes_in_text(_), do: []

  @doc """
  Checks if an identity can use premium emojis.
  Access granted if their tier includes custom_emoji OR they have an active emoji subscription.
  """
  def can_use_premium_emojis?(identity) do
    tier_allows = Hybridsocial.Premium.TierLimits.limit(identity, :custom_emoji) == true
    tier_allows || has_emoji_subscription?(identity.id)
  end

  defp has_emoji_subscription?(identity_id) do
    now = DateTime.utc_now()

    Hybridsocial.Premium.Subscription
    |> where(
      [s],
      s.identity_id == ^identity_id and
        s.plan == "emoji" and
        s.status == "active" and
        (is_nil(s.expires_at) or s.expires_at > ^now)
    )
    |> Repo.exists?()
  end

  @doc """
  Validates that the user can use any premium emojis in the given text.
  Returns :ok or {:error, shortcodes} with the list of disallowed shortcodes.
  """
  def validate_premium_emoji_access(text, identity) do
    premium_used = premium_shortcodes_in_text(text)

    if premium_used == [] || can_use_premium_emojis?(identity) do
      :ok
    else
      {:error, premium_used}
    end
  end

  @doc """
  Replaces `:shortcode:` patterns in text with image tags for HTML rendering.
  """
  def render_emojis_in_text(text) when is_binary(text) do
    emojis = list_emojis()
    emoji_map = Map.new(emojis, fn e -> {e.shortcode, e.image_url} end)

    Regex.replace(~r/:([a-zA-Z0-9_]+):/, text, fn full_match, shortcode ->
      case Map.get(emoji_map, shortcode) do
        nil ->
          full_match

        image_url ->
          ~s(<img class="custom-emoji" src="#{image_url}" alt=":#{shortcode}:" title=":#{shortcode}:" />)
      end
    end)
  end

  def render_emojis_in_text(text), do: text
end
