defmodule Mix.Tasks.Identity.Bootstrap do
  @shortdoc "Create the `identity` Postgres role + schema (idempotent)"

  @moduledoc """
  Creates the `identity` Postgres role and schema, idempotently, using superuser credentials from `BOOTSTRAP_PG_*` environment variables.
  """

  use Mix.Task
  use Boundary, exports: []

  @bootstrap_sql_path Path.join([__DIR__, "..", "..", "..", "priv", "repo", "bootstrap.sql"])

  @doc "Runs priv/repo/bootstrap.sql against Postgres to create the `identity` role and schema."
  @impl Mix.Task
  def run(_args) do
    {:ok, _} = Application.ensure_all_started(:postgrex)

    # Defaults match .devcontainer/docker-compose.yml's postgres service.
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
      Mix.shell().info("identity.bootstrap: executing statement...")
      Postgrex.query!(conn, statement, [])
    end)

    Mix.shell().info(
      "identity.bootstrap: done — role \"identity\" and schema \"identity\" are in place."
    )
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
