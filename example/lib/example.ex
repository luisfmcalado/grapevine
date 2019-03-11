defmodule Example do
  use Application

  def start(_, _) do
    opts = [
      name: :gsp1,
      rounds: 2,
      level: 2,
      gc: 10000,
      ttl: 30000,
      membership_module: Grapevine.Node,
      membership_opts: [
        mfa: {Grapevine, :add, [:gsp1]}
      ]
    ]

    [
      %{
        id: Grapevine,
        start: {Grapevine, :start_link, [
                   Grapevine.Gossip.Rumor,
                   Grapevine.DummyHandler,
                   opts]}
      }
    ] ++ children()
    |> Supervisor.start_link(strategy: :one_for_one)
  end

  defp default_topology,
    do: [
    example: [
      strategy: Cluster.Strategy.Epmd,
      config: [hosts: [:"node1@127.0.0.1", :"node2@127.0.0.1", :"node3@127.0.0.1"]]
    ]
  ]

  defp children() do
    topologies = Application.get_env(:libcluster, :topologies, default_topology())

    [{Cluster.Supervisor, [topologies, [name: Bastate.Cluster]]}]
  end
end
