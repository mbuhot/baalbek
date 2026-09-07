defmodule App.MixProject do
  use Mix.Project

  def project do
    [app: :app, version: "0.1.0", deps: deps()]
  end

  defp deps do
    [
      {:lib, path: "../lib"},
      {:facade, path: "../facade"},
      {:phoenix, "~> 1.8"},
      {:fixtures, path: "../lib/test/fixtures", only: [:dev, :test]}
    ]
  end
end
