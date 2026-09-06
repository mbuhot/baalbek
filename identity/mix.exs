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
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Identity.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ash, "~> 3.0"},
      {:ash_postgres, "~> 2.0"},
      {:boundary, "~> 0.10", runtime: false},
      # Not yet published to Hex (verified: GET https://hex.pm/api/packages/ash_boundary
      # -> 404) — pinned to a commit sha on `main` (no tags exist in the repo either)
      # rather than `branch: "main"`, so the dependency is reproducible the same way a
      # Hex version pin would be.
      {:ash_boundary,
       git: "https://github.com/mbuhot/ash_boundary.git",
       ref: "8e358e3f292725151eb03e147150db4750c498ac"}
    ]
  end
end
