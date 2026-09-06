defmodule PricingNative.MixProject do
  use Mix.Project

  def project do
    [
      app: :pricing_native,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      # See core/mix.exs's comment on why :boundary must precede
      # Mix.compilers() rather than follow it.
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
    [
      {:rustler, "~> 0.38"},
      {:boundary, "~> 0.10", runtime: false}
    ]
  end
end
