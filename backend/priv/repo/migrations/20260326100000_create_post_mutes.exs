defmodule Hybridsocial.Repo.Migrations.CreatePostMutes do
  use Ecto.Migration

  def change do
    create table(:post_mutes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :post_id, references(:posts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :identity_id, references(:identities, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:post_mutes, [:post_id, :identity_id])
    create index(:post_mutes, [:identity_id])
  end
end
