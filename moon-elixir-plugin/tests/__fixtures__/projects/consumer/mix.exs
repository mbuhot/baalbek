defmodule Consumer.MixProject do
  use Mix.Project

  def project do
    [app: :consumer, version: "0.1.0", deps: [{:unevaluable, path: "../unevaluable"}]]
  end
end
