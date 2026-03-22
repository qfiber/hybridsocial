defmodule Hybridsocial.Portability.AccountDeletion do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "account_deletions" do
    field :reason, :string
    field :scheduled_for, :utc_datetime_usec
    field :cancelled_at, :utc_datetime_usec
    field :executed_at, :utc_datetime_usec

    belongs_to :identity, Hybridsocial.Accounts.Identity

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(deletion, attrs) do
    deletion
    |> cast(attrs, [:identity_id, :reason, :scheduled_for])
    |> validate_required([:identity_id, :scheduled_for])
    |> unique_constraint(:identity_id)
    |> foreign_key_constraint(:identity_id)
  end

  def cancel_changeset(deletion) do
    deletion
    |> change(cancelled_at: DateTime.utc_now())
  end

  def execute_changeset(deletion) do
    deletion
    |> change(executed_at: DateTime.utc_now())
  end
end
