defmodule TimelineFacade.MixProject do
  use Mix.Project

  # timeline's runtime OTP closure, produced by `moon run timeline:build`. Each
  # one becomes a real Mix path dependency below, so a `mix release` bundles
  # it. See
  # ../server/spec/decisions/adr-0001-release-assembly-and-gleam-packaging.md.
  #
  # Written out rather than read from that directory: moon-elixir-plugin
  # evaluates this manifest while it builds the project graph, before
  # `timeline:build` writes the directory, so the manifest has to answer the
  # same on a cold graph as on a warm one. `check_shipment!/0` fails on drift.
  # See ../spec/decisions/adr-0010-third-party-deps-compile-in-their-own-task.md.
  @timeline_otp_apps ~w(
    backoff
    exception
    gleam_erlang
    gleam_otp
    gleam_stdlib
    gleam_time
    opentelemetry_api
    pg_types
    pgo
    pog
    timeline
  )

  @timeline_otp Path.expand("../timeline/build/otp", __DIR__)

  def project do
    [
      app: :timeline_facade,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      # :boundary must precede Mix.compilers() (see core/mix.exs).
      compilers: [:boundary] ++ Mix.compilers(),
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [{:boundary, "~> 0.10", runtime: false} | timeline_deps()]
  end

  defp timeline_deps do
    check_shipment!()
    Enum.map(@timeline_otp_apps, &timeline_dep/1)
  end

  # `compile: "exit 0"` and `override: true` are load bearing; the ADR above
  # says why.
  defp timeline_dep(otp_app) do
    {String.to_atom(otp_app),
     path: Path.join(@timeline_otp, otp_app), compile: "exit 0", override: true}
  end

  # The directory is absent until `timeline:build` writes it, and holds exactly
  # @timeline_otp_apps after that.
  defp check_shipment! do
    case File.ls(@timeline_otp) do
      {:ok, shipped} ->
        if Enum.sort(shipped) != @timeline_otp_apps do
          Mix.raise("""
          timeline_facade: @timeline_otp_apps does not match #{@timeline_otp}.
          shipped: #{Enum.join(Enum.sort(shipped), " ")}
          listed:  #{Enum.join(@timeline_otp_apps, " ")}
          Update the list in mix.exs, or the closure in ../timeline.
          """)
        end

      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        Mix.raise("timeline_facade: cannot read #{@timeline_otp}: #{:file.format_error(reason)}")
    end
  end
end
