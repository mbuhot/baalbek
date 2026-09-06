# Loads timeline's compiled Gleam/Erlang output onto this project's code
# path. Runs on every mix command. See spec/decisions/adr-0001-gleam-elixir-interop.md
# for why (Mix path deps need a manifest file timeline doesn't have; not a
# real dependency, so building timeline first is timeline:test's job, via
# the dependsOn in this project's moon.yml).
timeline_build_erlang =
  Path.join([__DIR__, "..", "timeline", "build", "dev", "erlang"])

if File.dir?(timeline_build_erlang) do
  # timeline's build dir also vendors copies of mix/elixir/eex/logger
  # (a transitive dev-dependency's doing). Skip any app already loaded, so
  # we never shadow the live Mix/Elixir/EEx/Logger with a stale copy.
  already_loaded =
    Application.loaded_applications() |> Enum.map(fn {name, _, _} -> name end) |> MapSet.new()

  timeline_build_erlang
  |> File.ls!()
  |> Enum.reject(&MapSet.member?(already_loaded, String.to_atom(&1)))
  |> Enum.each(fn otp_app_dir ->
    ebin = Path.join([timeline_build_erlang, otp_app_dir, "ebin"])
    if File.dir?(ebin), do: Code.prepend_path(ebin)
  end)
end

defmodule TimelineFacade.MixProject do
  use Mix.Project

  def project do
    [
      app: :timeline_facade,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      # :boundary must precede Mix.compilers() (see core/mix.exs).
      compilers: [:boundary] ++ Mix.compilers(),
      # Keeps timeline's prepended ebin dirs on the code path after
      # compilation (Mix would otherwise prune them; timeline isn't a
      # declared Mix dep).
      prune_code_paths: false,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:boundary, "~> 0.10", runtime: false}
    ]
  end
end
