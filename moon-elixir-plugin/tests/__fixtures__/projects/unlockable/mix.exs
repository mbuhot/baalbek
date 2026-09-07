defmodule Unlockable.MixProject do
  use Mix.Project

  def project do
    [app: :unlockable, version: "0.1.0", deps: [{:lib, path: "../lib"}]]
  end
end
