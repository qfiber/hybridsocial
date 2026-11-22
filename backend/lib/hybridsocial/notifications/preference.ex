defmodule Hybridsocial.Notifications.Preference do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @member_types ~w(follow follow_request reaction boost quote reply mention poll_ended group_invite group_application page_invite report admin)

  # Staff email alerts (Notifications.StaffEmail) and whether each emails a
  # staff member who never set a preference. Only staff may store these.
  @staff_email_defaults %{
    "admin_new_report" => true,
    "admin_new_appeal" => false,
    "admin_pending_account" => false,
    "admin_backup_failed" => false,
    "moderation_queue" => false
  }

  @valid_types @member_types ++ Map.keys(@staff_email_defaults)

  @doc "True for the staff-only email alert types."
  def staff_type?(type), do: Map.has_key?(@staff_email_defaults, type)

  @doc "Staff alert type => email default, for staff who haven't chosen."
  def staff_email_defaults, do: @staff_email_defaults

  def staff_email_default(type), do: Map.get(@staff_email_defaults, type, false)

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
