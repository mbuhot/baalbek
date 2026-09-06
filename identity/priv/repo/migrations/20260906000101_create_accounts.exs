defmodule Identity.Repo.Migrations.CreateAccounts do
  use Ecto.Migration

  # Runs as the `identity` role (config/config.exs), whose search_path is
  # set to schema `identity` by priv/repo/bootstrap.sql — no schema prefix
  # needed here, the table lands in `identity.accounts`.
  def change do
    create table(:accounts, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :text, null: false
      add :email, :text, null: false
      add :role, :text, null: false
      add :hashed_password, :text, null: false

      timestamps(type: :utc_datetime)
    end

    # Named to match what AshPostgres expects for the `identity :unique_email`
    # declared on Identity.Accounts.Account (the <table>_<identity>_index
    # convention `mix ash_postgres.generate_migrations` itself would use) —
    # this is the constraint name Ash's error-translation layer looks for
    # when converting a Postgres unique_violation into a friendly
    # Ash.Error.Changes.InvalidAttribute instead of a raw Ecto.ConstraintError.
    create unique_index(:accounts, [:email], name: :accounts_unique_email_index)
  end
end
