defmodule Hybridsocial.Moderation.BlockedHashtag do
  @moduledoc """
  An admin block on a hashtag. Each action includes the ones before it:

    * `no_trending` - never listed in trending
    * `hide` - posts carrying the tag also leave public timelines, Streams and
      search, and the tag page and tag search come up empty. Followers of the
      author still see those posts.
    * `reject` - new posts carrying the tag are also refused from other servers
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @actions ~w(no_trending hide reject)
  @hiding_actions ~w(hide reject)

  # Kept in sync with Posts.extract_hashtags/1: a name that could never be
  # extracted from a post could never match one either.
  @name_format ~r/^\p{L}[\p{L}\p{M}\p{N}_]{0,100}$/u

  schema "blocked_hashtags" do
    field :name, :string
    field :action, :string, default: "no_trending"
    field :reason, :string
    field :created_by, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def hiding_actions, do: @hiding_actions

  def changeset(blocked_hashtag, attrs) do
    blocked_hashtag
    |> cast(attrs, [:name, :action, :reason, :created_by])
    |> validate_required([:name, :action])
    |> update_change(:name, &normalize_name/1)
    |> validate_format(:name, @name_format, message: "must be a single hashtag")
    |> validate_inclusion(:action, @actions)
    |> unique_constraint(:name)
  end

  def normalize_name(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.trim_leading("#")
    |> String.downcase()
  end

  def normalize_name(name), do: name
end
