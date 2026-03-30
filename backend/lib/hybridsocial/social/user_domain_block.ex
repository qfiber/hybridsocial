defmodule Hybridsocial.Social.UserDomainBlock do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_domain_blocks" do
    belongs_to :identity, Hybridsocial.Accounts.Identity
    field :domain, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(block, attrs) do
    block
    |> cast(attrs, [:identity_id, :domain])
    |> validate_required([:identity_id, :domain])
    |> update_change(:domain, &String.downcase/1)
    |> unique_constraint([:identity_id, :domain])
    |> foreign_key_constraint(:identity_id)
  end
end
