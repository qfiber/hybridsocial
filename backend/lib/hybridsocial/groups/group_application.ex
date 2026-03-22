defmodule Hybridsocial.Groups.GroupApplication do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "group_applications" do
    field :answers, :map, default: %{}

    field :status, Ecto.Enum,
      values: [:pending, :approved, :rejected, :auto_approved],
      default: :pending

    field :created_at, :utc_datetime_usec
    field :reviewed_at, :utc_datetime_usec

    belongs_to :group, Hybridsocial.Groups.Group
    belongs_to :identity, Hybridsocial.Accounts.Identity
    belongs_to :reviewer, Hybridsocial.Accounts.Identity, foreign_key: :reviewed_by
  end

  def changeset(application, attrs) do
    application
    |> cast(attrs, [:group_id, :identity_id, :answers, :status, :reviewed_by, :reviewed_at])
    |> validate_required([:group_id, :identity_id])
    |> put_created_at()
    |> foreign_key_constraint(:group_id)
    |> foreign_key_constraint(:identity_id)
  end

  def review_changeset(application, attrs) do
    application
    |> cast(attrs, [:status, :reviewed_by])
    |> validate_required([:status, :reviewed_by])
    |> put_change(:reviewed_at, DateTime.utc_now() |> DateTime.truncate(:microsecond))
  end

  defp put_created_at(changeset) do
    if get_field(changeset, :created_at) do
      changeset
    else
      put_change(changeset, :created_at, DateTime.utc_now() |> DateTime.truncate(:microsecond))
    end
  end
end
