defmodule Escaping.MixProject do
  use Mix.Project

  def project do
    [app: :escaping, version: "0.1.0", deps: deps()]
  end

  defp deps do
    [
      {:outside, path: "../../outside"},
      {:absolute, path: "/opt/absolute"},
      {:escaping, path: "."},
      {:unowned, path: "../vendor/unowned"}
    ]
  end
end
