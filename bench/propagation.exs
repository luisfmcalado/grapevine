import Grapevine.Support.Wait
import Grapevine.Support.Cluster
import Grapevine.Support.Bench

alias Grapevine.Support.Generator

setup_distributed()

nodes = 2
stop_slaves(nodes)
wait(fn -> Node.list() != [] end, 500, 20) |> assert("no nodes connected?")

opts = [
  delta: 10,
  rounds: 1,
  level: 1
]

init_slaves(nodes, Support.BenchHandler, opts)
wait(fn -> !slaves_connected?(nodes) end, 500, 20) |> assert("slaves connected?")
Generator.start_link()

Benchee.run(%{
  "add" => fn ->
    value = Generator.next()
    Grapevine.add({:gsp1, :slave_0@localhost}, value)
    wait(fn -> !in_sync?(nodes, value + 3) end, 10, 200) |> assert("in sync?")
  end
})
