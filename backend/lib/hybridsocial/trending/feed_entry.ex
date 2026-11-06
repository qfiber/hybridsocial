defmodule Hybridsocial.Trending.FeedEntry do
  @moduledoc """
  One post's place in Explore's precomputed Trending feed. See
  `Hybridsocial.Trending.ExploreFeed`.
  """
  use Ecto.Schema

  @primary_key {:post_id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "trending_feed_entries" do
    field :slot, :float
    field :score, :float
    field :is_local, :boolean
    field :reason_type, :string
    field :reason_tag, :string
    field :active, :boolean, default: true
    field :computed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end
end
