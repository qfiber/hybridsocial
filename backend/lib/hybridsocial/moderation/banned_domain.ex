defmodule Hybridsocial.Moderation.BannedDomain do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:domain, :string, autogenerate: false}
  @foreign_key_type :binary_id

  @types ~w(email federation both)

  schema "banned_domains" do
    field :type, :string
    field :reason, :string

    belongs_to :creator, Hybridsocial.Accounts.Identity, foreign_key: :created_by

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(banned_domain, attrs) do
    banned_domain
    |> cast(attrs, [:domain, :type, :reason, :created_by])
    |> validate_required([:domain, :type])
    |> validate_inclusion(:type, @types)
    |> update_change(:domain, &String.downcase/1)
  end
end
