defmodule Hybridsocial.Moderation.ContentFilter do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @types ~w(word phrase regex)
  @actions ~w(flag reject replace)
  @contexts ~w(posts usernames bios all)
  @scopes ~w(all local remote)

  schema "content_filters" do
    field :type, :string
    field :pattern, :string
    field :action, :string
    field :replacement, :string
    field :context, :string, default: "all"
    field :scope, :string, default: "all"

    belongs_to :creator, Hybridsocial.Accounts.Identity, foreign_key: :created_by

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(filter, attrs) do
    filter
    |> cast(attrs, [:type, :pattern, :action, :replacement, :context, :scope, :created_by])
    |> validate_required([:type, :pattern, :action])
    |> validate_length(:pattern, max: 1000)
    |> validate_length(:replacement, max: 500)
    |> validate_inclusion(:type, @types)
    |> validate_inclusion(:action, @actions)
    |> validate_inclusion(:context, @contexts)
    |> validate_inclusion(:scope, @scopes)
    |> validate_replacement()
  end

  defp validate_replacement(changeset) do
    action = get_field(changeset, :action)
    replacement = get_field(changeset, :replacement)

    if action == "replace" && (is_nil(replacement) || replacement == "") do
      add_error(changeset, :replacement, "is required when action is replace")
    else
      changeset
    end
  end
end
