defmodule Hybridsocial.Auth.Permission do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "permissions" do
    field :name, :string
    field :description, :string
    field :category, :string
  end
end
