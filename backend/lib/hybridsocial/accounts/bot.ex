defmodule Hybridsocial.Accounts.Bot do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:identity_id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "bots" do
    field :webhook_url, :string
    field :webhook_secret_hash, :string
    field :auto_approve_follows, :boolean, default: false
    field :description, :string
    field :source_code_url, :string
    field :is_active, :boolean, default: true

    belongs_to :identity, Hybridsocial.Accounts.Identity,
      foreign_key: :identity_id,
      references: :id,
      define_field: false

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(bot, attrs) do
    bot
    |> cast(attrs, [:webhook_url, :auto_approve_follows, :description, :source_code_url, :is_active])
    |> validate_url(:webhook_url)
    |> validate_url(:source_code_url)
    |> validate_length(:description, max: 1000)
  end

  defp validate_url(changeset, field) do
    case get_change(changeset, field) do
      nil ->
        changeset

      url ->
        case URI.parse(url) do
          %URI{scheme: scheme} when scheme in ["http", "https"] -> changeset
          _ -> add_error(changeset, field, "must be a valid URL")
        end
    end
  end
end
