defmodule Hybridsocial.Repo.Migrations.AddAutoDeleteToIdentities do
  use Ecto.Migration

  def change do
    # Per-user automatic post deletion (#254). NULL months = off (the default).
    # `auto_delete_enabled_at` marks when it was switched on: only posts
    # published after that are swept, so turning it on never touches the
    # posts that already existed.
    alter table(:identities) do
      add :auto_delete_after_months, :integer
      add :auto_delete_enabled_at, :utc_datetime_usec
    end

    create index(:identities, [:id],
             where: "auto_delete_after_months IS NOT NULL",
             name: :identities_auto_delete_enabled_index
           )
  end
end
