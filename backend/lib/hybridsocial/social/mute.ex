defmodule Hybridsocial.Social.Mute do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "mutes" do
    field :mute_notifications, :boolean, default: true
    field :expires_at, :utc_datetime_usec

    belongs_to :muter, Hybridsocial.Accounts.Identity
    belongs_to :muted, Hybridsocial.Accounts.Identity

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(mute, attrs) do
    mute
    |> cast(attrs, [:muter_id, :muted_id, :mute_notifications, :expires_at])
    |> validate_required([:muter_id, :muted_id])
    |> validate_not_self()
    |> unique_constraint([:muter_id, :muted_id])
    |> foreign_key_constraint(:muter_id)
    |> foreign_key_constraint(:muted_id)
  end

  defp validate_not_self(changeset) do
    muter_id = get_field(changeset, :muter_id)
    muted_id = get_field(changeset, :muted_id)

    if muter_id && muted_id && muter_id == muted_id do
      add_error(changeset, :muted_id, "cannot mute yourself")
    else
      changeset
    end
  end
end
