defmodule Core.MixProject do
  use Mix.Project

  def project do
    [
      app: :core,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      # `boundary` must be listed BEFORE Mix.compilers(), not after: it hooks
      # itself in via `Mix.Task.Compiler.after_compiler(:elixir, ...)` and
      # `after_compiler(:app, ...)`, and those registrations only fire for
      # compiler passes that run *after* :boundary's own `run/1` executes.
      # Appending it after Mix.compilers() (a mistake made once during this
      # stage's development, confirmed by a deliberate boundary-violating
      # call that :boundary silently failed to flag until the order was
      # fixed) means :app has already finished by the time :boundary
      # registers its callback, so the check never runs. It only sees
      # compiled lib code, never test/, because ExUnit files are scripts
      # evaluated at runtime rather than traced.
      compilers: [:boundary] ++ Mix.compilers(),
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Core.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp aliases do
    [bootstrap: ["core.bootstrap", "ecto.create --quiet", "ecto.migrate --quiet"]]
  end

  defp deps do
    [
      {:ash, "~> 3.0"},
      {:ash_postgres, "~> 2.0"},
      {:boundary, "~> 0.10", runtime: false},
      {:ash_boundary, "~> 0.1"},
      {:cucumber, "~> 1.0", only: [:dev, :test]}
    ]
  end
end
