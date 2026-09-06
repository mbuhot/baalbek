defmodule Billing.Repo.Migrations.CreateInvoiceLineItems do
  use Ecto.Migration

  def change do
    create table(:invoice_line_items, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :invoice_id, references(:invoices, type: :uuid, on_delete: :delete_all), null: false
      add :description, :text, null: false
      add :quantity, :integer, null: false, default: 1
      add :unit_amount, :numeric, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:invoice_line_items, [:invoice_id])
  end
end
