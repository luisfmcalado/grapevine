defmodule Grapevine.MixProject do
  use Mix.Project

  def project do
    [
      app: :grapevine,
      version: "0.1.0",
      elixir: "~> 1.7",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      source_url: "https://github.com/luisfmcalado/grapevine",
      package: package(),
      description: """
      Gossip protocol for Elixir
      """
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    [
      files: ["lib", "mix.exs", "README*", "LICENSE*"],
      maintainers: ["Luis Calado"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/luisfmcalado/grapevine"}
    ]
  end

  defp deps do
    [
      {:dialyze, "~> 0.2.0"},
      {:ex_doc, ">= 0.0.0", only: :dev}
    ]
  end
end
