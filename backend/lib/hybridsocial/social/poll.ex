defmodule Hybridsocial.Social.Poll do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "polls" do
    field :multiple_choice, :boolean, default: false
    field :expires_at, :utc_datetime_usec
    field :voters_count, :integer, default: 0

    belongs_to :post, Hybridsocial.Social.Post
    has_many :options, Hybridsocial.Social.PollOption
    has_many :votes, Hybridsocial.Social.PollVote

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(poll, attrs) do
    poll
    |> cast(attrs, [:post_id, :multiple_choice, :expires_at])
    |> validate_required([:post_id])
    |> foreign_key_constraint(:post_id)
  end
end
