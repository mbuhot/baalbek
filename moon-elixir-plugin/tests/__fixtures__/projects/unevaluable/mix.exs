defmodule Unevaluable.MixProject do
  use Mix.Project

  def project do
    [app: :unevaluable, version: "0.1.0", deps: deps()]
  end

  # The shape timeline_facade has on a clean checkout: the manifest needs a
  # build directory that no task has produced yet, so it raises.
  defp deps do
    Mix.raise("unevaluable: ../nowhere does not exist. Run `moon run other:package` first.")
  end
end
