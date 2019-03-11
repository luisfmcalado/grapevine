import Grapevine.Support.Wait
import Grapevine.Support.Cluster
import Grapevine.Support.Bench

alias Grapevine.Support.DummyHandler
alias Grapevine.Gossip.Entropy
alias Grapevine.Gossip.Rumor

setup = fn gossip, nodes, size ->
  values =
    Enum.reduce(0..(size - 1), [], fn n, acc ->
      acc ++ [{n, %{value: n}}]
    end)

  {gossip, nodes, size, values}
end

inputs = fn gossip ->
  %{
    "#{gossip}: 10 updates and 2 nodes" => setup.(gossip, 2, 10),
    "#{gossip}: 10 updates and 4 nodes" => setup.(gossip, 4, 10),
    "#{gossip}: 10 updates and 8 nodes" => setup.(gossip, 8, 10),
    "#{gossip}: 100 updates and 2 nodes" => setup.(gossip, 2, 100),
    "#{gossip}: 100 updates and 4 nodes" => setup.(gossip, 4, 100),
    "#{gossip}: 100 updates and 8 nodes" => setup.(gossip, 8, 100),
    "#{gossip}: 1000 updates and 2 nodes" => setup.(gossip, 2, 1000),
    "#{gossip}: 1000 updates and 4 nodes" => setup.(gossip, 4, 1000),
    "#{gossip}: 1000 updates and 8 nodes" => setup.(gossip, 8, 1000),
    "#{gossip}: 10_000 updates and 2 nodes" => setup.(gossip, 2, 10_000),
    "#{gossip}: 10_000 updates and 4 nodes" => setup.(gossip, 4, 10_000),
    "#{gossip}: 10_000 updates and 8 nodes" => setup.(gossip, 8, 10_000)
  }
end

before = fn {gossip, nodes, size, values} ->
  setup_distributed()
  stop_slaves(nodes)
  wait(fn -> Node.list() != [] end, 500, 20) |> assert("no nodes connected?")

  opts = [
    delta: 10,
    level: nodes,
    rounds: nodes + round(nodes / 2)
  ]

  init_slaves(nodes, gossip, DummyHandler, opts)
  wait(fn -> !slaves_connected?(nodes) end, 500, 20) |> assert("slaves connected?")

  {nodes, size, values}
end

Benchee.run(
  %{
    "add" => fn {nodes, size, values} ->
      Enum.each(values, fn value ->
        Grapevine.add({:gsp1, :slave_0@localhost}, value, :infinity)
      end)

      wait(fn -> !in_sync?(nodes, size) end, 10, 30000) |> assert("in sync?")
    end
  },
  inputs: Map.merge(inputs.(Rumor), inputs.(Entropy)),
  before_each: &before.(&1)
)
