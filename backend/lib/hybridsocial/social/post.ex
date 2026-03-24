defmodule Hybridsocial.Social.Post do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_visibilities ~w(public followers group direct list)
  @valid_post_types ~w(text media video_stream poll article)

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
    field :is_pinned, :boolean, default: false

    field :ap_id, :string

    field :edited_at, :utc_datetime_usec
    field :edit_expires_at, :utc_datetime_usec
    field :scheduled_at, :utc_datetime_usec
    field :published_at, :utc_datetime_usec
    field :deleted_at, :utc_datetime_usec

    belongs_to :identity, Hybridsocial.Accounts.Identity
    belongs_to :parent, __MODULE__
    belongs_to :root, __MODULE__
    belongs_to :quote, __MODULE__

    has_many :reactions, Hybridsocial.Social.Reaction
    has_many :boosts, Hybridsocial.Social.Boost
    has_many :revisions, Hybridsocial.Social.PostRevision
    has_one :poll, Hybridsocial.Social.Poll

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(post, attrs, opts \\ []) do
    char_limit = Keyword.get(opts, :char_limit, 5000)

    post
    |> cast(attrs, [
      :content,
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
      :identity_id,
      :scheduled_at,
      :ap_id
    ])
    |> validate_required([:identity_id])
    |> validate_inclusion(:visibility, @valid_visibilities)
    |> validate_inclusion(:post_type, @valid_post_types)
    |> validate_content_for_type()
    |> validate_length(:content, max: char_limit)
    |> validate_length(:spoiler_text, max: 500)
    |> validate_length(:language, max: 5)
    |> generate_content_html()
    |> foreign_key_constraint(:identity_id)
    |> foreign_key_constraint(:parent_id)
    |> foreign_key_constraint(:root_id)
    |> foreign_key_constraint(:quote_id)
    |> unique_constraint(:ap_id)
  end

  def edit_changeset(post, attrs, opts \\ []) do
    char_limit = Keyword.get(opts, :char_limit, 5000)

    post
    |> cast(attrs, [:content, :spoiler_text, :sensitive, :language])
    |> validate_edit_window(post)
    |> validate_content_for_type()
    |> validate_length(:content, max: char_limit)
    |> validate_length(:spoiler_text, max: 500)
    |> generate_content_html()
    |> put_change(:edited_at, DateTime.utc_now() |> DateTime.truncate(:microsecond))
  end

  def soft_delete_changeset(post) do
    post
    |> change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:microsecond))
  end

  defp validate_content_for_type(changeset) do
    post_type = get_field(changeset, :post_type)

    if post_type != "media" do
      validate_required(changeset, [:content])
    else
      changeset
    end
  end

  defp validate_edit_window(changeset, post) do
    case post.edit_expires_at do
      nil ->
        add_error(changeset, :edit_expires_at, "edit window has expired")

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
