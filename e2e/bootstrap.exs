# Creates every Postgres role, schema and table the release needs, using only
# what the release itself ships.
#
# Run inside the release container by the `bootstrap` service in
# docker-compose.yml: `bin/server eval 'Code.require_file("/e2e/bootstrap.exs")'`.
# Idempotent, like the `mix *.bootstrap` tasks it stands in for.

defmodule E2E.Bootstrap do
  @moduledoc "Bootstraps the e2e database from inside the release."

  @apps [:core, :identity, :billing]
  @repos [core: Core.Data.Repo, identity: Identity.Repo, billing: Billing.Repo]

  def run do
    roles_and_schemas()
    migrations()
    timeline()
    IO.puts("e2e bootstrap: done")
  end

  # Each app's own priv/repo/bootstrap.sql, shipped in the release, executed as
  # the superuser — the same file and the same statement splitting as
  # `mix <app>.bootstrap`, so the two paths cannot drift.
  defp roles_and_schemas do
    {:ok, _} = Application.ensure_all_started(:postgrex)

    {:ok, conn} =
      Postgrex.start_link(
        hostname: System.get_env("BOOTSTRAP_PG_HOST", "localhost"),
        port: String.to_integer(System.get_env("BOOTSTRAP_PG_PORT", "5432")),
        username: System.get_env("BOOTSTRAP_PG_USER", "postgres"),
        password: System.get_env("BOOTSTRAP_PG_PASSWORD", "postgres"),
        database: System.get_env("BOOTSTRAP_PG_DATABASE", "baalbek")
      )

    Enum.each(@apps, fn app ->
      app
      |> Application.app_dir("priv/repo/bootstrap.sql")
      |> File.read!()
      |> split_statements()
      |> Enum.each(&Postgrex.query!(conn, &1, []))

      IO.puts("e2e bootstrap: #{app} role + schema ready")
    end)
  end

  # Starting the app starts its Repo, which the migrator then uses; the
  # migration files travel in the release under each app's priv/repo/migrations.
  defp migrations do
    Enum.each(@repos, fn {app, repo} ->
      {:ok, _} = Application.ensure_all_started(app)
      Ecto.Migrator.run(repo, :up, all: true)
      IO.puts("e2e bootstrap: #{app} migrations up")
    end)
  end

  # `timeline` is a Gleam application, so its bootstrap is a Gleam function in
  # the release, not a Mix task. Calling it also proves the release loaded it.
  defp timeline do
    :"timeline@bootstrap".main()
  end

  # Splits only on lines containing just ";", so a dollar-quoted DO block's internal ";"s survive intact.
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

E2E.Bootstrap.run()
