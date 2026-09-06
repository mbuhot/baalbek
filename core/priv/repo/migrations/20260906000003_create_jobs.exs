defmodule Core.Data.Repo.Migrations.CreateJobs do
  use Ecto.Migration

  def change do
    create table(:jobs, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :site_id, references(:sites, type: :uuid, on_delete: :delete_all), null: false
      add :title, :text, null: false
      add :description, :text
      add :status, :text, null: false, default: "requested"
      add :scheduled_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:jobs, [:site_id])
  end
end
