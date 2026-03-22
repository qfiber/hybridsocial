defmodule Hybridsocial.Federation.InstancePolicy do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:domain, :string, autogenerate: false}

  @valid_policies ~w(allow silence suspend block_media force_nsfw)

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
    |> validate_inclusion(:policy, @valid_policies)
  end
end
