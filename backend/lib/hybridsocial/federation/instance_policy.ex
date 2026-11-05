defmodule Hybridsocial.Federation.InstancePolicy do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:domain, :string, autogenerate: false}

  @valid_policies ~w(allow silence suspend block_media force_nsfw)

  # Policies match on the exact host of a remote actor, so anything else (a
  # handle, a profile URL) would save happily and then never match anything.
  @domain_format ~r/^(?=.{1,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/

  schema "instance_policies" do
    field :policy, :string
    field :reason, :string
    field :created_by, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(instance_policy, attrs) do
    instance_policy
    |> cast(attrs, [:domain, :policy, :reason, :created_by])
    |> validate_required([:domain, :policy])
    |> update_change(:domain, &normalize_domain/1)
    |> validate_format(:domain, @domain_format,
      message: "must be a domain like example.com, not an account handle or profile URL"
    )
    |> validate_inclusion(:policy, @valid_policies)
  end

  @doc """
  Reduces harmless variations (case, whitespace, a bare `https://host/`) to the
  host. Handles and URLs with a path are left as they are so that validation
  rejects them: narrowing `@bob@evil.example` down to `evil.example` would turn
  an action against one account into a block of the whole instance.
  """
  def normalize_domain(domain) when is_binary(domain) do
    domain
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/^https?:\/\//, "")
    |> String.replace(~r/\/$/, "")
  end

  def normalize_domain(domain), do: domain
end
