defmodule Hybridsocial.Accounts.Organization do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:identity_id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "organizations" do
    field :website, :string
    field :category, :string

    belongs_to :identity, Hybridsocial.Accounts.Identity,
      foreign_key: :identity_id,
      references: :id,
      define_field: false

    belongs_to :owner, Hybridsocial.Accounts.Identity

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(org, attrs) do
    org
    |> cast(attrs, [:website, :category])
    |> validate_url(:website)
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
