defmodule Hybridsocial.Moderation.Appeal do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @action_types ~w(suspension silencing shadow_ban post_removal warning)
  @statuses ~w(pending approved rejected)

  schema "moderation_appeals" do
    field :action_type, :string
    field :reason, :string
    field :status, :string, default: "pending"
    field :reviewed_at, :utc_datetime_usec
    field :response, :string

    belongs_to :identity, Hybridsocial.Accounts.Identity
    belongs_to :reviewer, Hybridsocial.Accounts.Identity, foreign_key: :reviewed_by

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(appeal, attrs) do
    appeal
    |> cast(attrs, [:identity_id, :action_type, :reason])
    |> validate_required([:identity_id, :action_type, :reason])
    |> validate_inclusion(:action_type, @action_types)
    |> validate_length(:reason, min: 10, max: 5000)
    |> foreign_key_constraint(:identity_id)
  end

  def review_changeset(appeal, attrs) do
    appeal
    |> cast(attrs, [:status, :reviewed_by, :reviewed_at, :response])
    |> validate_required([:status, :reviewed_by, :reviewed_at])
    |> validate_inclusion(:status, ["approved", "rejected"])
    |> validate_length(:response, max: 5000)
    |> foreign_key_constraint(:reviewed_by)
  end

  def action_types, do: @action_types
  def statuses, do: @statuses
end
