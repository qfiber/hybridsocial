defmodule Hybridsocial.Moderation.QueuedItem do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_item_types ~w(post account media)
  @valid_sources ~w(content_filter auto_report trust_level manual)
  @valid_severities ~w(low medium high)
  @valid_statuses ~w(pending approved rejected escalated)

  schema "moderation_queued_items" do
    field :item_type, :string
    field :item_id, :binary_id
    field :source, :string
    field :reason, :string
    field :severity, :string, default: "medium"
    field :status, :string, default: "pending"
    field :reviewed_at, :utc_datetime_usec

    belongs_to :reviewed_by_identity, Hybridsocial.Accounts.Identity, foreign_key: :reviewed_by

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(queued_item, attrs) do
    queued_item
    |> cast(attrs, [
      :item_type,
      :item_id,
      :source,
      :reason,
      :severity,
      :status,
      :reviewed_by,
      :reviewed_at
    ])
    |> validate_required([:item_type, :item_id, :source, :reason])
    |> validate_inclusion(:item_type, @valid_item_types)
    |> validate_inclusion(:source, @valid_sources)
    |> validate_inclusion(:severity, @valid_severities)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_length(:reason, max: 5000)
  end

  def approve_changeset(queued_item, reviewer_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    queued_item
    |> change(status: "approved", reviewed_by: reviewer_id, reviewed_at: now)
  end

  def reject_changeset(queued_item, reviewer_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    queued_item
    |> change(status: "rejected", reviewed_by: reviewer_id, reviewed_at: now)
  end

  def escalate_changeset(queued_item) do
    queued_item
    |> change(status: "escalated")
  end

  def item_types, do: @valid_item_types
  def sources, do: @valid_sources
  def severities, do: @valid_severities
  def statuses, do: @valid_statuses
end
