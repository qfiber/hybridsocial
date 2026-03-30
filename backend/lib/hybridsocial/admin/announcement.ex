defmodule Hybridsocial.Admin.Announcement do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Hybridsocial.Repo

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "announcements" do
    field :content, :string
    field :starts_at, :utc_datetime_usec
    field :ends_at, :utc_datetime_usec
    field :published, :boolean, default: true
    field :created_by, Ecto.UUID

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(announcement, attrs) do
    announcement
    |> cast(attrs, [:content, :starts_at, :ends_at, :published, :created_by])
    |> validate_required([:content])
    |> validate_length(:content, min: 1, max: 5000)
  end

  def list_all do
    __MODULE__
    |> order_by([a], desc: a.inserted_at)
    |> Repo.all()
  end

  def create(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  def update(id, attrs) do
    case Repo.get(__MODULE__, id) do
      nil -> {:error, :not_found}
      ann -> ann |> changeset(attrs) |> Repo.update()
    end
  end

  def delete(id) do
    case Repo.get(__MODULE__, id) do
      nil -> {:error, :not_found}
      ann -> Repo.delete(ann)
    end
  end
end
