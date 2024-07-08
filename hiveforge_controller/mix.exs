defmodule HiveforgeController.MixProject do
  use Mix.Project

  def project do
    [
      app: :hiveforge_controller,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def release do
    [
      hiveforge_controller: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent],
        steps: [:assemble, :tar]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :runtime_tools, :ecto, :ecto_sql],
      mod: {HiveforgeController.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:httpoison, "~> 2.2"},
      {:plug_cowboy, "~> 2.7"},
      {:jason, "~> 1.4"},
      {:ecto, "~> 3.11"},
      {:postgrex, "~> 0.18"},
      {:ecto_sql, "~> 3.11"},
      {:joken, "~> 2.6"}
    ]
  end
end
