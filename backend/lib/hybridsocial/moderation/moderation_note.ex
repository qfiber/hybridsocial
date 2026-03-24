defmodule Hybridsocial.Moderation.ModerationNote do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "moderation_notes" do
    field :content, :string

    belongs_to :target_identity, Hybridsocial.Accounts.Identity
    belongs_to :author, Hybridsocial.Accounts.Identity

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(note, attrs) do
    note
    |> cast(attrs, [:target_identity_id, :author_id, :content])
    |> validate_required([:target_identity_id, :author_id, :content])
    |> validate_length(:content, min: 1, max: 10_000)
    |> foreign_key_constraint(:target_identity_id)
    |> foreign_key_constraint(:author_id)
  end
end
