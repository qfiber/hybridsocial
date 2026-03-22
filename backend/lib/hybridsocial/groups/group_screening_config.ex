defmodule Hybridsocial.Groups.GroupScreeningConfig do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:group_id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "group_screening_config" do
    field :require_profile_image, :boolean, default: false
    field :min_account_age_days, :integer, default: 0
    field :questions, {:array, :map}, default: []
    field :auto_approve_rules, :map, default: %{}

    belongs_to :group, Hybridsocial.Groups.Group,
      foreign_key: :group_id,
      references: :id,
      define_field: false
  end

  def changeset(config, attrs) do
    config
    |> cast(attrs, [
      :group_id,
      :require_profile_image,
      :min_account_age_days,
      :questions,
      :auto_approve_rules
    ])
    |> validate_required([:group_id])
    |> validate_number(:min_account_age_days, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:group_id)
  end
end
