defmodule Identity.MixProject do
  use Mix.Project

  def project do
    [
      app: :identity,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      # `boundary` MUST be listed BEFORE Mix.compilers(), not after — see
      # core/mix.exs's header comment for the full story: appending it
      # after Mix.compilers() means :app has already finished by the time
      # :boundary registers its `after_compiler` callback, so the check
      # silently never runs. Verified fixed here the same way core did.
      compilers: [:boundary] ++ Mix.compilers(),
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Identity.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp aliases do
    [bootstrap: ["identity.bootstrap", "ecto.create --quiet", "ecto.migrate --quiet"]]
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
