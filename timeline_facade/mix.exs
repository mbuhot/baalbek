defmodule TimelineFacade.MixProject do
  use Mix.Project

  # timeline's compiled OTP applications, produced by `moon run
  # timeline:package`. Each one becomes a real Mix path dependency below, so
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

  # `compile: "exit 0"` is a no-op valid in both `sh -c` and `cmd /c`: these
  # directories are already compiled. It must be a command and not `false` —
  # only the command branch of Mix.Tasks.Deps.Compile links a dep's ebin/
  # into _build, and without that link Mix reports "could not find an app
  # file". `override: true` means these vendored copies win over any Hex
  # dependency of the same name; see the ADR for which names that covers.
  defp timeline_deps do
    case File.ls(@timeline_otp) do
      {:ok, otp_apps} ->
        Enum.map(otp_apps, fn otp_app ->
          {String.to_atom(otp_app),
           path: Path.join(@timeline_otp, otp_app), compile: "exit 0", override: true}
        end)

      {:error, :enoent} ->
        Mix.raise("""
        timeline_facade: #{@timeline_otp} does not exist.
        Run `moon run timeline:package` (or bash timeline/scripts/package-otp.sh) first.
        """)

      {:error, reason} ->
        Mix.raise("timeline_facade: cannot read #{@timeline_otp}: #{:file.format_error(reason)}")
    end
  end
end
