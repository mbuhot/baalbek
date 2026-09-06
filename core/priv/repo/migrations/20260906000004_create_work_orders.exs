defmodule Core.Data.Repo.Migrations.CreateWorkOrders do
  use Ecto.Migration

  def change do
    create table(:work_orders, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :job_id, references(:jobs, type: :uuid, on_delete: :delete_all), null: false
      add :summary, :text, null: false
      add :status, :text, null: false, default: "open"
      add :completed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:work_orders, [:job_id])
  end
end
