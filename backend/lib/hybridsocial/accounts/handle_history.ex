defmodule Hybridsocial.Accounts.HandleHistory do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "handle_history" do
    field :old_handle, :string
    field :changed_at, :utc_datetime_usec
    field :reserved_until, :utc_datetime_usec

    belongs_to :identity, Hybridsocial.Accounts.Identity
  end
end
