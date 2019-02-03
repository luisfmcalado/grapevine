defmodule Example.MixProject do
  use Mix.Project

  def project do
    [
      app: :example,
      version: "0.1.0",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Example, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:grapevine, path: ".."},
      {:libcluster, "~> 3.0"}
    ]
  end
end
