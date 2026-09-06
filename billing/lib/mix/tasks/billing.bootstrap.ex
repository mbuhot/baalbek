defmodule Mix.Tasks.Billing.Bootstrap do
  @shortdoc "Create the `billing` Postgres role + schema (idempotent)"

  @moduledoc """
  Runs `priv/repo/bootstrap.sql` (verbatim, no separate copy) against
  Postgres as a superuser, creating the dedicated `billing` role and its
  `billing` schema/grants (PLAN.md "Data layer"; see that file's own
  header comment for the full rationale). Verbatim copy of
  `core.bootstrap`'s pattern (core/lib/mix/tasks/core.bootstrap.ex),
  renamed core -> billing throughout.

  This is a structural, once-per-database step distinct from
  `mix ecto.migrate` — it must run before migrations, and needs superuser
  credentials (the `billing` role it creates cannot create roles/schemas
  itself). Ordinary `Billing.Repo` connections (used by migrations, the
  app, and tests) always connect as the unprivileged `billing` role — see
  config/config.exs.

  ## Usage

      mix billing.bootstrap

  ## Configuration

  Superuser connection details come from environment variables (all
  optional, defaulting to match `.devcontainer/docker-compose.yml`'s
  `postgres` service):

    * `BOOTSTRAP_PG_HOST` (default `localhost`)
    * `BOOTSTRAP_PG_PORT` (default `5432`)
    * `BOOTSTRAP_PG_USER` (default `postgres`)
    * `BOOTSTRAP_PG_PASSWORD` (default `postgres`)
    * `BOOTSTRAP_PG_DATABASE` (default `baalbek`)

  These are deliberately named apart from `BILLING_PG_*`
  (config/config.exs) so the two can never be confused: `BILLING_PG_*` is
  the low-privilege runtime role, `BOOTSTRAP_PG_*` is the one-time
  superuser connection.
  """

  use Mix.Task
  use Boundary, exports: []

  @bootstrap_sql_path Path.join([__DIR__, "..", "..", "..", "priv", "repo", "bootstrap.sql"])

  @impl Mix.Task
  def run(_args) do
    {:ok, _} = Application.ensure_all_started(:postgrex)

    opts = [
      hostname: System.get_env("BOOTSTRAP_PG_HOST", "localhost"),
      port: String.to_integer(System.get_env("BOOTSTRAP_PG_PORT", "5432")),
      username: System.get_env("BOOTSTRAP_PG_USER", "postgres"),
      password: System.get_env("BOOTSTRAP_PG_PASSWORD", "postgres"),
      database: System.get_env("BOOTSTRAP_PG_DATABASE", "baalbek")
    ]

    {:ok, conn} = Postgrex.start_link(opts)

    @bootstrap_sql_path
    |> File.read!()
    |> split_statements()
    |> Enum.each(fn statement ->
      Mix.shell().info("billing.bootstrap: executing statement...")
      Postgrex.query!(conn, statement, [])
    end)

    Mix.shell().info(
      "billing.bootstrap: done — role \"billing\" and schema \"billing\" are in place."
    )
  end

  # Splits bootstrap.sql on lines that contain only ";" (see that file's
  # header comment). A naive split on every ";" would also split inside
  # the DO block's dollar-quoted body (it contains its own `;`-terminated
  # statements), which is exactly what this convention avoids: Postgres
  # only ever sees one full statement per Postgrex.query!/3 call.
  defp split_statements(sql) do
    sql
    |> String.split(~r/^;[ \t]*$/m)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or comment_only?(&1)))
  end

  defp comment_only?(statement) do
    statement
    |> String.split("\n")
    |> Enum.all?(fn line ->
      trimmed = String.trim(line)
      trimmed == "" or String.starts_with?(trimmed, "--")
    end)
  end
end
