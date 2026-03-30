defmodule Hybridsocial.Ads.Ad do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_placements ~w(sidebar feed banner)

  schema "ads" do
    field :title, :string
    field :description, :string
    field :image_url, :string
    field :link_url, :string
    field :placement, :string, default: "sidebar"
    field :priority, :integer, default: 0
    field :starts_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec
    field :is_active, :boolean, default: true
    field :impressions, :integer, default: 0
    field :clicks, :integer, default: 0

    belongs_to :created_by, Hybridsocial.Accounts.Identity

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(ad, attrs) do
    ad
    |> cast(attrs, [:title, :description, :image_url, :link_url, :placement, :priority, :starts_at, :expires_at, :is_active, :created_by_id])
    |> validate_required([:title, :link_url])
    |> validate_inclusion(:placement, @valid_placements)
    |> validate_length(:title, max: 200)
    |> validate_length(:description, max: 500)
    |> validate_length(:link_url, max: 2048)
  end
end
