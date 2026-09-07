defmodule Facade.MixProject do
  use Mix.Project

  # A dependency list that does not exist until Mix evaluates this file. The
  # plugin shells out to Elixir, so these resolve like any other path dep.
  @built Path.expand("../lib/priv/otp", __DIR__)

  def project do
    [app: :facade, version: "0.1.0", deps: deps()]
  end

  defp deps do
    [{:jason, "~> 1.4"} | Enum.map(File.ls!(@built), &{String.to_atom(&1), path: Path.join(@built, &1)})]
  end
end
