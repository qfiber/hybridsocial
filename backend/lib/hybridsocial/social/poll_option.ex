defmodule Hybridsocial.Social.PollOption do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "poll_options" do
    field :text, :string
    field :position, :integer
    field :votes_count, :integer, default: 0

    belongs_to :poll, Hybridsocial.Social.Poll
  end

  def changeset(option, attrs) do
    option
    |> cast(attrs, [:poll_id, :text, :position])
    |> validate_required([:poll_id, :text, :position])
    |> foreign_key_constraint(:poll_id)
  end
end
