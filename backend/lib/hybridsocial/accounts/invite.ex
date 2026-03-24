defmodule Hybridsocial.Accounts.Invite do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "invites" do
    field :code, :string
    field :max_uses, :integer
    field :uses, :integer, default: 0
    field :expires_at, :utc_datetime_usec
    field :disabled, :boolean, default: false

    belongs_to :creator, Hybridsocial.Accounts.Identity, foreign_key: :created_by

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(invite, attrs) do
    invite
    |> cast(attrs, [:max_uses, :expires_at, :created_by])
    |> validate_required([:created_by])
    |> put_change(:code, generate_code())
    |> unique_constraint(:code)
  end

  defp generate_code do
    :crypto.strong_rand_bytes(6)
    |> Base.encode32(padding: false, case: :lower)
    |> binary_part(0, 8)
  end
end
