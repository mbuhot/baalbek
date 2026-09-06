defmodule Server.MixProject do
  use Mix.Project

  def project do
    [
      app: :server,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      # `boundary` must precede Mix.compilers() — see core/mix.exs's header
      # comment for the full story (this project mirrors it verbatim).
      compilers: [:boundary] ++ Mix.compilers(),
      aliases: aliases(),
      # PLAN.md "Boundary enforcement, in-app and cross-app": `server` is the
      # first app with real Mix path deps on sibling apps, so this is where
      # cross-app checking turns on. Only these five apps are checked (not
      # every transitive Hex dependency) — boundary's own docs call this
      # "Restricting usage of external apps".
      boundary: [
        default: [
          check: [
            apps: [:core, :identity, :billing, :pricing_native, :timeline_facade]
          ]
        ]
      ],
      deps: deps()
    ]
  end

  def cli do
    [preferred_envs: ["test.changed": :test]]
  end

  def application do
    [
      mod: {Server.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    ["test.changed": &test_changed/1]
  end

  # Runs only the test paths mirroring the lib/ files changed since the base
  # ref; ../test-paths.py owns the mapping (seed.md §7.3).
  defp test_changed(args) do
    {out, 0} =
      System.cmd("python3", [
        Path.join(__DIR__, "../test-paths.py"),
        "--select",
        "--app",
        Path.basename(__DIR__) | args
      ])

    case String.split(out, "\n", trim: true) do
      [] ->
        Mix.shell().info("test.changed: nothing changed in this app — no tests selected")

      paths ->
        Mix.shell().info("""
        test.changed: running #{Enum.join(paths, " ")}
          Path selection is a pre-merge gate, not a proof of coverage: a test that \
        covers this change from another path is not selected. Run `mix test` for the \
        full suite before relying on this.
        """)

        Mix.Task.run("test", paths)
    end
  end

  defp deps do
    [
      # Path deps on all five domain apps (PLAN.md Component inventory:
      # "depends on all domain apps"). Only `core` gets a wired HTTP surface
      # this stage; the others are real build-time deps regardless.
      {:core, path: "../core"},
      {:identity, path: "../identity"},
      {:billing, path: "../billing"},
      {:pricing_native, path: "../pricing_native"},
      {:timeline_facade, path: "../timeline_facade"},
      {:phoenix, "~> 1.8"},
      {:bandit, "~> 1.0"},
      {:ash_json_api, "~> 1.7"},
      # ash_json_api lists this as `optional: true` (only pulled in if the
      # top-level app also depends on it) — needed for the `open_api` route
      # and the `mix openapi.spec.json` task (see moon.yml).
      {:open_api_spex, "~> 3.16"},
      {:jason, "~> 1.4"},
      {:boundary, "~> 0.10", runtime: false},
      {:cucumber, "~> 1.0", only: [:dev, :test]}
    ]
  end
end
