defmodule TimelineFacade.MixProject do
  use Mix.Project

  # timeline's compiled OTP applications, produced by `moon run
  # timeline:build`. Each one becomes a real Mix path dependency below, so
  # a `mix release` bundles it. See
  # ../server/spec/decisions/adr-0001-release-assembly-and-gleam-packaging.md.
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

  # Must not raise: an unevaluable manifest infers no `dependsOn`, and before
  # `moon run timeline:build` the directory is absent on every cold tree. The
  # fallback names one application of eleven, which is why moon.yml lets Mix
  # check this project's dependencies itself.
  defp timeline_deps do
    case File.ls(@timeline_otp) do
      {:ok, otp_apps} ->
        Enum.map(otp_apps, &timeline_dep/1)

      {:error, :enoent} ->
        [timeline_dep("timeline")]

      {:error, reason} ->
        Mix.raise("timeline_facade: cannot read #{@timeline_otp}: #{:file.format_error(reason)}")
    end
  end

  # `compile: "exit 0"` and `override: true` are load bearing; the ADR above
  # says why.
  defp timeline_dep(otp_app) do
    {String.to_atom(otp_app),
     path: Path.join(@timeline_otp, otp_app), compile: "exit 0", override: true}
  end
end
