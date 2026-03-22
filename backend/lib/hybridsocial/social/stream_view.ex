defmodule Hybridsocial.Social.StreamView do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_sources ~w(feed profile trending direct_link)

  schema "stream_views" do
    field :watch_duration, :float
    field :total_duration, :float
    field :completed, :boolean, default: false
    field :replayed, :boolean, default: false
    field :source, :string, default: "feed"

    belongs_to :post, Hybridsocial.Social.Post
    belongs_to :identity, Hybridsocial.Accounts.Identity

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(stream_view, attrs) do
    stream_view
    |> cast(attrs, [:post_id, :identity_id, :watch_duration, :total_duration, :completed, :replayed, :source])
    |> validate_required([:post_id, :watch_duration, :total_duration])
    |> validate_number(:watch_duration, greater_than_or_equal_to: 0)
    |> validate_number(:total_duration, greater_than: 0)
    |> validate_inclusion(:source, @valid_sources)
    |> foreign_key_constraint(:post_id)
    |> foreign_key_constraint(:identity_id)
  end
end
