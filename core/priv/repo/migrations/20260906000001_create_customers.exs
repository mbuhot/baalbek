defmodule Core.Data.Repo.Migrations.CreateCustomers do
  use Ecto.Migration

  # Runs as the `core` role (config/config.exs), whose search_path is set
  # to schema `core` by priv/repo/bootstrap.sql — no schema prefix needed
  # here, the table lands in `core.customers`.
  def change do
    create table(:customers, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :text, null: false
      add :email, :text
      add :phone, :text

      timestamps(type: :utc_datetime)
    end
  end
end
