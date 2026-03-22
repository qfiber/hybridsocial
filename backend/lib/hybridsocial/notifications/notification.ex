defmodule Hybridsocial.Notifications.Notification do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_types ~w(follow follow_request reaction boost quote reply mention poll_ended group_invite group_application report admin)
  @valid_target_types ~w(post group conversation)

  schema "notifications" do
    field :type, :string
    field :target_type, :string
    field :target_id, :binary_id
    field :read, :boolean, default: false

    belongs_to :recipient, Hybridsocial.Accounts.Identity
    belongs_to :actor, Hybridsocial.Accounts.Identity

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [:recipient_id, :actor_id, :type, :target_type, :target_id, :read])
    |> validate_required([:recipient_id, :actor_id, :type])
    |> validate_inclusion(:type, @valid_types)
    |> validate_inclusion(:target_type, @valid_target_types ++ [nil])
    |> foreign_key_constraint(:recipient_id)
    |> foreign_key_constraint(:actor_id)
  end
end
