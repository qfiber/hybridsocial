defmodule Hybridsocial.Repo.Migrations.AddUserContentFiltersAndBirthday do
  use Ecto.Migration

  def change do
    # User-level content filters
    create table(:user_content_filters, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :identity_id, references(:identities, type: :binary_id, on_delete: :delete_all), null: false
      add :phrase, :string, null: false
      add :context, {:array, :string}, default: ["home", "public", "notifications", "thread"]
      add :action, :string, default: "warn"  # warn | hide
      add :whole_word, :boolean, default: false
      add :expires_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:user_content_filters, [:identity_id])

    # Birthday on identities
    alter table(:identities) do
      add :birthday, :date
    end
  end
end
