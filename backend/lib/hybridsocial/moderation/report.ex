defmodule Hybridsocial.Moderation.Report do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @categories ~w(spam harassment hate_speech illegal misinformation other)
  @statuses ~w(pending investigating resolved dismissed)

  schema "reports" do
    field :target_type, :string
    field :target_id, :binary_id
    field :category, :string
    field :description, :string
    field :status, :string, default: "pending"
    field :action_taken, :string
    field :federated, :boolean, default: false
    field :resolved_at, :utc_datetime_usec

    belongs_to :reporter, Hybridsocial.Accounts.Identity
    belongs_to :reported, Hybridsocial.Accounts.Identity
    belongs_to :assigned_moderator, Hybridsocial.Accounts.Identity, foreign_key: :assigned_to

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(report, attrs) do
    report
    |> cast(attrs, [
      :reporter_id,
      :reported_id,
      :target_type,
      :target_id,
      :category,
      :description,
      :federated
    ])
    |> validate_required([:reporter_id, :reported_id, :category])
    |> validate_inclusion(:category, @categories)
    |> foreign_key_constraint(:reporter_id)
    |> foreign_key_constraint(:reported_id)
  end

  def assign_changeset(report, moderator_id) do
    report
    |> change(assigned_to: moderator_id, status: "investigating")
  end

  def resolve_changeset(report, action_taken) do
    report
    |> change(status: "resolved", action_taken: action_taken, resolved_at: DateTime.utc_now())
  end

  def dismiss_changeset(report) do
    report
    |> change(status: "dismissed", resolved_at: DateTime.utc_now())
  end

  def categories, do: @categories
  def statuses, do: @statuses
end
