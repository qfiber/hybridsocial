defmodule Hybridsocial.Social.PollVote do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "poll_votes" do
    belongs_to :poll, Hybridsocial.Social.Poll
    belongs_to :option, Hybridsocial.Social.PollOption
    belongs_to :identity, Hybridsocial.Accounts.Identity

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(vote, attrs) do
    vote
    |> cast(attrs, [:poll_id, :option_id, :identity_id])
    |> validate_required([:poll_id, :option_id, :identity_id])
    |> unique_constraint([:poll_id, :identity_id, :option_id])
    |> foreign_key_constraint(:poll_id)
    |> foreign_key_constraint(:option_id)
    |> foreign_key_constraint(:identity_id)
  end
end
