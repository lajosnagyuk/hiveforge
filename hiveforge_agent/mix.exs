defmodule HiveforgeAgent.MixProject do
  use Mix.Project

  def project do
    [
      app: :hiveforge_agent,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {HiveforgeAgent.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:httpoison, "~> 2.2"},
      {:jason, "~> 1.4"},
      {:quantum, "~> 3.5"},
      {:hackney, "~> 1.20"},
      {:ssl_verify_fun, "~> 1.1"},
      {:b3, "~> 0.1"}
    ]
  end
end
