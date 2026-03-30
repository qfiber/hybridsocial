defmodule Hybridsocial.Social.UserContentFilter do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_actions ~w(warn hide)
  @valid_contexts ~w(home public notifications thread)

  schema "user_content_filters" do
    belongs_to :identity, Hybridsocial.Accounts.Identity
    field :phrase, :string
    field :context, {:array, :string}, default: ["home", "public", "notifications", "thread"]
    field :action, :string, default: "warn"
    field :whole_word, :boolean, default: false
    field :expires_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(filter, attrs) do
    filter
    |> cast(attrs, [:identity_id, :phrase, :context, :action, :whole_word, :expires_at])
    |> validate_required([:identity_id, :phrase])
    |> validate_inclusion(:action, @valid_actions)
    |> validate_length(:phrase, min: 1, max: 200)
    |> validate_contexts()
    |> foreign_key_constraint(:identity_id)
  end

  defp validate_contexts(changeset) do
    case get_field(changeset, :context) do
      nil -> changeset
      contexts ->
        if Enum.all?(contexts, &(&1 in @valid_contexts)) do
          changeset
        else
          add_error(changeset, :context, "invalid context values")
        end
    end
  end
end
