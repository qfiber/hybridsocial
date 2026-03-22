defmodule Hybridsocial.Notifications.Preference do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_types ~w(follow follow_request reaction boost quote reply mention poll_ended group_invite group_application report admin)

  schema "notification_preferences" do
    field :type, :string
    field :email, :boolean, default: false
    field :push, :boolean, default: true
    field :in_app, :boolean, default: true

    belongs_to :identity, Hybridsocial.Accounts.Identity

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(preference, attrs) do
    preference
    |> cast(attrs, [:identity_id, :type, :email, :push, :in_app])
    |> validate_required([:identity_id, :type])
    |> validate_inclusion(:type, @valid_types)
    |> unique_constraint([:identity_id, :type])
    |> foreign_key_constraint(:identity_id)
  end
end
