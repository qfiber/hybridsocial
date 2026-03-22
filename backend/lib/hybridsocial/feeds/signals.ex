defmodule Hybridsocial.Feeds.Signals do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_interaction_signals" do
    field :interaction_count, :integer, default: 0
    field :last_interaction, :utc_datetime_usec
    field :content_tags, :map, default: %{}

    belongs_to :identity, Hybridsocial.Accounts.Identity
    belongs_to :target_identity, Hybridsocial.Accounts.Identity

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(signal, attrs) do
    signal
    |> cast(attrs, [
      :identity_id,
      :target_identity_id,
      :interaction_count,
      :last_interaction,
      :content_tags
    ])
    |> validate_required([:identity_id, :target_identity_id])
    |> unique_constraint([:identity_id, :target_identity_id])
    |> foreign_key_constraint(:identity_id)
    |> foreign_key_constraint(:target_identity_id)
  end
end
