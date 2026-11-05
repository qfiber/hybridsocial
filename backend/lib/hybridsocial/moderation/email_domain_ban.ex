defmodule Hybridsocial.Moderation.EmailDomainBan do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @domain_format ~r/^(?=.{1,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/

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
    |> update_change(:domain, &normalize_domain/1)
    |> validate_format(:domain, @domain_format,
      message: "must be a domain like example.com, not an email address or URL"
    )
    |> unique_constraint(:domain)
  end

  # Signup compares against the exact part of the address after the @, so anything
  # but a bare lowercase domain would save and then never block a signup.
  defp normalize_domain(domain) when is_binary(domain) do
    domain |> String.trim() |> String.trim_leading("@") |> String.downcase()
  end

  defp normalize_domain(domain), do: domain
end
