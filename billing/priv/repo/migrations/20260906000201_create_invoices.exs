defmodule Billing.Repo.Migrations.CreateInvoices do
  use Ecto.Migration

  # Runs as the `billing` role (config/config.exs), whose search_path is
  # set to schema `billing` by priv/repo/bootstrap.sql — no schema prefix
  # needed here, the table lands in `billing.invoices`.
  #
  # `job_id` is a bare uuid column with no `references/2` — deliberately
  # no foreign key across schemas (see Billing.Invoicing's moduledoc).
  def change do
    create table(:invoices, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :job_id, :uuid, null: false
      add :status, :text, null: false, default: "draft"
      add :currency, :text, null: false, default: "USD"
      add :total_amount, :numeric, null: false, default: 0
      add :issued_at, :utc_datetime
      add :paid_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:invoices, [:job_id])
  end
end
