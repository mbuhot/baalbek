defmodule Core.Data.Repo.Migrations.CreateSites do
  use Ecto.Migration

  def change do
    create table(:sites, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :customer_id, references(:customers, type: :uuid, on_delete: :delete_all), null: false
      add :name, :text, null: false
      add :address, :text

      timestamps(type: :utc_datetime)
    end

    create index(:sites, [:customer_id])
  end
end
