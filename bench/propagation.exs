import Grapevine.Support.Wait
import Grapevine.Support.Cluster
import Grapevine.Support.Bench

alias Grapevine.Support.Generator
alias Grapevine.Support.DummyHandler
alias Grapevine.Gossip.Entropy
alias Grapevine.Gossip.Rumor

nodes = 2

opts = [
  delta: 10,
  rounds: 1,
  level: 1
]

Benchee.run(
  %{
    "propagation" => fn _ ->
      value = Generator.next()
      Grapevine.add({:gsp1, :slave_0@localhost}, value, value)
      wait(fn -> !in_sync?(nodes, value + 1) end, 10, 200) |> assert("in sync?")
    end
  },
  inputs: %{
    "Entropy" => Entropy,
    "Rumor" => Rumor
  },
  before_scenario: fn gossip ->
    setup_distributed()
    stop_slaves(nodes)
    init_slaves(nodes, gossip, DummyHandler, opts)
    wait(fn -> !slaves_connected?(nodes) end, 500, 20) |> assert("slaves connected?")
    Generator.start_link()
    Generator.reset()
  end
)
