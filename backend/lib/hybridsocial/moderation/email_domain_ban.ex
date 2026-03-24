defmodule Hybridsocial.Moderation.EmailDomainBan do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "email_domain_bans" do
    field :domain, :string
    field :reason, :string

    belongs_to :creator, Hybridsocial.Accounts.Identity, foreign_key: :created_by

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(email_domain_ban, attrs) do
    email_domain_ban
    |> cast(attrs, [:domain, :reason, :created_by])
    |> validate_required([:domain])
    |> update_change(:domain, &String.downcase/1)
    |> unique_constraint(:domain)
  end
end
