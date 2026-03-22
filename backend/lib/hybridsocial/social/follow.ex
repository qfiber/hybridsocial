defmodule Hybridsocial.Social.Follow do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "follows" do
    field :status, Ecto.Enum, values: [:pending, :accepted, :rejected]
    field :notify, :boolean, default: true

    belongs_to :follower, Hybridsocial.Accounts.Identity
    belongs_to :followee, Hybridsocial.Accounts.Identity

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(follow, attrs) do
    follow
    |> cast(attrs, [:follower_id, :followee_id, :status, :notify])
    |> validate_required([:follower_id, :followee_id, :status])
    |> validate_not_self()
    |> unique_constraint([:follower_id, :followee_id])
    |> foreign_key_constraint(:follower_id)
    |> foreign_key_constraint(:followee_id)
  end

  def status_changeset(follow, status) do
    follow
    |> change(status: status)
  end

  defp validate_not_self(changeset) do
    follower_id = get_field(changeset, :follower_id)
    followee_id = get_field(changeset, :followee_id)

    if follower_id && followee_id && follower_id == followee_id do
      add_error(changeset, :followee_id, "cannot follow yourself")
    else
      changeset
    end
  end
end
