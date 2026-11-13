defmodule Hybridsocial.Social.Post do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_visibilities ~w(public unlisted followers group direct list)
  @valid_post_types ~w(text media video_stream audio poll article)

  schema "posts" do
    field :post_type, :string, default: "text"
    field :content, :string
    field :content_html, :string
    field :visibility, :string, default: "public"
    field :sensitive, :boolean, default: false
    field :spoiler_text, :string
    field :language, :string
    field :group_id, :binary_id
    field :page_id, :binary_id
    field :list_id, :binary_id

    field :reply_count, :integer, default: 0
    field :boost_count, :integer, default: 0
    field :reaction_count, :integer, default: 0
    # Denormalized pending-reports count. Maintained by the Moderation
    # context on report create/resolve/dismiss. Only surfaced to
    # staff-gated UI — regular users don't see it on their timeline.
    field :open_report_count, :integer, default: 0
    field :is_pinned, :boolean, default: false

    # Per-post custom-emoji manifest. Each entry is a map with at
    # least `shortcode` and `url`; the renderer swaps `:shortcode:`
    # text in `content`/`content_html` for an <img> at render time.
    # Federated posts populate this from the AP `tag` array's Emoji
    # entries; local posts can leave it empty (instance emojis are
    # picked up from the global custom_emojis table instead).
    field :emojis, {:array, :map}, default: []

    field :ap_id, :string
    field :parent_ap_id, :string

    field :edited_at, :utc_datetime_usec
    field :edit_expires_at, :utc_datetime_usec
    field :scheduled_at, :utc_datetime_usec
    field :published_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec
    field :deleted_at, :utc_datetime_usec

    # Thread-bump timestamp. Initialized to `published_at` on insert
    # and bumped to `now()` whenever a reply lands on this post or
    # any of its descendants. Timelines order by this instead of
    # `published_at` so threads with new activity surface back up.
    # Intentionally NOT touched on edits — typo fixes shouldn't
    # promote an old post.
    field :last_activity_at, :utc_datetime_usec

    # Admin-moderation flags. `hidden_at` drops the post from public
    # timelines without deleting it (permalink still resolves).
    # `replies_locked_at` rejects new replies against this post or
    # its descendants (checked at reply-create time).
    field :hidden_at, :utc_datetime_usec
    field :hidden_by, Ecto.UUID
    field :replies_locked_at, :utc_datetime_usec
    field :replies_locked_by, Ecto.UUID

    belongs_to :identity, Hybridsocial.Accounts.Identity
    belongs_to :parent, __MODULE__
    belongs_to :root, __MODULE__
    belongs_to :quote, __MODULE__
    # Per-image reply targeting: a reply can pin itself to one of the
    # parent's media attachments so the post detail view can split
    # the thread by image. Null = post-level reply, default behaviour.
    belongs_to :target_media, Hybridsocial.Media.MediaFile

    has_many :reactions, Hybridsocial.Social.Reaction
    has_many :boosts, Hybridsocial.Social.Boost
    has_many :revisions, Hybridsocial.Social.PostRevision
    has_many :media_attachments, Hybridsocial.Media.MediaFile
    has_many :mentions, Hybridsocial.Social.PostMention
    has_one :poll, Hybridsocial.Social.Poll

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(post, attrs, opts \\ []) do
    char_limit = Keyword.get(opts, :char_limit, 5000)

    post
    |> cast(attrs, [
      :id,
      :content,
      # Posts.create_post pre-renders content_html at the author's
      # tier-gated markdown level (free → plaintext, verified_pro →
      # full GFM with tables). If we don't cast this field, the
      # pre-rendered value never enters the changeset; the fallback
      # in generate_content_html/1 re-renders at the default
      # :basic level, silently stripping tables, headings, images.
      :content_html,
      :post_type,
      :visibility,
      :sensitive,
      :spoiler_text,
      :language,
      :group_id,
      :page_id,
      :list_id,
      :parent_id,
      :root_id,
      :quote_id,
      :target_media_id,
      :identity_id,
      :scheduled_at,
      :ap_id,
      :parent_ap_id,
      :last_activity_at,
      :emojis
    ])
    |> normalize_content()
    |> validate_required([:identity_id])
    |> validate_inclusion(:visibility, @valid_visibilities)
    |> validate_inclusion(:post_type, @valid_post_types)
    |> validate_content_for_type()
    |> validate_length(:content, max: char_limit)
    |> validate_length(:spoiler_text, max: 500)
    |> validate_length(:language, max: 5)
    # Remote ids are unbounded; cap them so an absurd one is a changeset
    # error, not a database error (a btree index entry tops out near 2.7 KB).
    |> validate_length(:ap_id, max: 2048, count: :bytes)
    |> validate_length(:parent_ap_id, max: 2048, count: :bytes)
    |> generate_content_html()
    |> foreign_key_constraint(:identity_id)
    |> foreign_key_constraint(:parent_id)
    |> foreign_key_constraint(:root_id)
    |> foreign_key_constraint(:quote_id)
    |> foreign_key_constraint(:target_media_id)
    |> unique_constraint(:ap_id)
  end

  def edit_changeset(post, attrs, opts \\ []) do
    char_limit = Keyword.get(opts, :char_limit, 5000)

    post
    |> cast(attrs, [:content, :content_html, :spoiler_text, :sensitive, :language])
    |> normalize_content()
    |> validate_edit_window(post)
    |> validate_content_for_type(Keyword.get(opts, :has_media, false))
    |> validate_length(:content, max: char_limit)
    |> validate_length(:spoiler_text, max: 500)
    |> generate_content_html()
    |> put_change(:edited_at, DateTime.utc_now() |> DateTime.truncate(:microsecond))
  end

  def soft_delete_changeset(post) do
    post
    |> change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:microsecond))
  end

  @doc "Reverses a soft delete by clearing `deleted_at`."
  def restore_changeset(post) do
    post
    |> change(deleted_at: nil)
  end

  @doc """
  Flips a scheduled post to "published now". Kept separate from the
  generic changeset so the scheduler's call site is explicit about
  what it's doing + lets `Posts.run_post_published_hooks/1` pattern
  match on the result.
  """
  def publish_changeset(post, published_at) do
    # Stamp last_activity_at alongside published_at so the newly-
    # published scheduled post lands in the correct spot on the
    # timeline instead of surfacing wherever its (nil) last_activity_at
    # happened to sort.
    post
    |> change(published_at: published_at, last_activity_at: published_at)
  end

  # Trim trailing whitespace + collapse runs of empty lines so a post
  # body doesn't end with phantom blank lines or a stray space after
  # the last word. Internal blank lines between paragraphs are kept
  # (one max), so paragraph breaks still survive — only the gratuitous
  # ones the user didn't mean to leave get cleaned up. Mirrors what
  # the spoiler_text fields do less aggressively (just trim).
  defp normalize_content(changeset) do
    changeset =
      case get_change(changeset, :content) do
        content when is_binary(content) ->
          # Per-line right-trim, then collapse 3+ blank lines down to
          # 2 (a single empty line separating paragraphs), then strip
          # leading/trailing whitespace from the whole body.
          cleaned =
            content
            |> String.split("\n")
            |> Enum.map(&String.trim_trailing/1)
            |> Enum.join("\n")
            |> String.replace(~r/\n{3,}/, "\n\n")
            |> String.trim()

          if cleaned == "",
            do: put_change(changeset, :content, nil),
            else: put_change(changeset, :content, cleaned)

        _ ->
          changeset
      end

    case get_change(changeset, :spoiler_text) do
      spoiler when is_binary(spoiler) ->
        put_change(changeset, :spoiler_text, String.trim(spoiler))

      _ ->
        changeset
    end
  end

  defp validate_content_for_type(changeset, has_media \\ false) do
    post_type = get_field(changeset, :post_type)

    # media, video_stream and audio posts can be caption-less — a photo,
    # clip, or voice memo doesn't need text. A post that HAS media is also
    # exempt regardless of post_type: a captioned image is stored as
    # post_type "text", so clearing its caption on edit must not demand
    # content when there's still an image (issue #26). Everything else
    # (text/poll/article with no media) requires content.
    if post_type in ["media", "video_stream", "audio"] or has_media do
      changeset
    else
      validate_required(changeset, [:content])
    end
  end

  defp validate_edit_window(changeset, post) do
    case post.edit_expires_at do
      nil ->
        # nil means unlimited editing
        changeset

      expires_at ->
        if DateTime.compare(DateTime.utc_now(), expires_at) == :gt do
          add_error(changeset, :edit_expires_at, "edit window has expired")
        else
          changeset
        end
    end
  end

  defp generate_content_html(changeset) do
    # Only generate if content_html isn't already set (Posts.create_post sets it via Sanitizer)
    case get_change(changeset, :content_html) do
      nil ->
        case get_change(changeset, :content) do
          nil ->
            changeset

          content ->
            put_change(
              changeset,
              :content_html,
              Hybridsocial.Content.Sanitizer.sanitize_post_content(content)
            )
        end

      _already_set ->
        changeset
    end
  end
end
