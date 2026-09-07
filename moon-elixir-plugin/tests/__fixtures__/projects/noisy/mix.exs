defmodule Noisy.MixProject do
  use Mix.Project

  def project do
    # Prints while Mix evaluates this file, and ends without a newline, so the
    # result must be found by its marker rather than by being the last line.
    IO.write("noise with no trailing newline")

    [app: :noisy, version: "0.1.0", deps: [{:lib, path: "../lib"}]]
  end
end
