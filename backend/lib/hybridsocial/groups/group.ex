defmodule Hybridsocial.Groups.Group do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "groups" do
    field :name, :string
    field :description, :string
    field :visibility, Ecto.Enum, values: [:public, :private, :local_only], default: :public

    field :join_policy, Ecto.Enum,
      values: [:open, :screening, :approval, :invite_only],
      default: :open

    field :ap_actor_url, :string
    field :public_key, :string
    field :private_key, :string
    field :avatar_url, :string
    field :header_url, :string
    field :member_count, :integer, default: 0
    field :post_count, :integer, default: 0
    field :deleted_at, :utc_datetime_usec

    belongs_to :creator, Hybridsocial.Accounts.Identity, foreign_key: :created_by

    has_many :members, Hybridsocial.Groups.GroupMember
    has_one :screening_config, Hybridsocial.Groups.GroupScreeningConfig

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(group, attrs) do
    group
    |> cast(attrs, [
      :name,
      :description,
      :visibility,
      :join_policy,
      :avatar_url,
      :header_url,
      :created_by
    ])
    |> validate_required([:name, :created_by])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:description, max: 5000)
    |> foreign_key_constraint(:created_by)
  end

  def update_changeset(group, attrs) do
    group
    |> cast(attrs, [:name, :description, :visibility, :join_policy, :avatar_url, :header_url])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:description, max: 5000)
  end

  def soft_delete_changeset(group) do
    group
    |> change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:microsecond))
  end
end
