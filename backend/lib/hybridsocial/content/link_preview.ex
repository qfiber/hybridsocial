defmodule Hybridsocial.Content.LinkPreview do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:url_hash, :string, autogenerate: false}

  schema "link_previews" do
    field :url, :string
    field :title, :string
    field :description, :string
    field :image_url, :string
    field :site_name, :string
    field :fetched_at, :utc_datetime_usec
    field :ttl, :integer, default: 86400

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(preview, attrs) do
    preview
    |> cast(attrs, [:url_hash, :url, :title, :description, :image_url, :site_name, :fetched_at, :ttl])
    |> validate_required([:url_hash, :url, :fetched_at])
  end
end
