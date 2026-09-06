ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Identity.Repo, :manual)

# Acceptance criteria live in spec/features (seed.md §8), not under test/.
Cucumber.compile_features!(
  features: ["spec/features/**/*.feature"],
  steps: ["spec/features/step_definitions/**/*.exs"],
  support: ["spec/features/support/**/*.exs"]
)
