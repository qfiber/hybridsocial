defmodule Hybridsocial.Social.AccountNote do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "account_notes" do
    belongs_to :author, Hybridsocial.Accounts.Identity
    belongs_to :target, Hybridsocial.Accounts.Identity
    field :content, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(note, attrs) do
    note
    |> cast(attrs, [:author_id, :target_id, :content])
    |> validate_required([:author_id, :target_id, :content])
    |> validate_length(:content, max: 2000)
    |> unique_constraint([:author_id, :target_id])
    |> foreign_key_constraint(:author_id)
    |> foreign_key_constraint(:target_id)
  end
end
