import Grapevine.Support.Wait
import Grapevine.Support.Cluster
import Grapevine.Support.Bench

setup = fn nodes, size ->
  values =
    Enum.reduce(0..(size - 1), [], fn n, acc ->
      acc ++ [%{value: n}]
    end)

  {nodes, size, values}
end

setup_distributed()

Benchee.run(
  %{
    "add" => fn {nodes, size, values} ->
      Enum.each(values, fn value ->
        Grapevine.add({:gsp1, :slave_0@localhost}, value)
      end)

      wait(fn -> !in_sync?(nodes, size) end, 10, 30000) |> assert("in sync?")
    end
  },
  inputs: %{
    "10 updates and 2 nodes" => setup.(2, 10),
    "10 updates and 4 nodes" => setup.(4, 10),
    "10 updates and 8 nodes" => setup.(8, 10),
    "100 updates and 2 nodes" => setup.(2, 100),
    "100 updates and 4 nodes" => setup.(4, 100),
    "100 updates and 8 nodes" => setup.(8, 100),
    "1000 updates and 2 nodes" => setup.(2, 1000),
    "1000 updates and 4 nodes" => setup.(4, 1000),
    "1000 updates and 8 nodes" => setup.(8, 1000),
    "10_000 updates and 2 nodes" => setup.(2, 10_000),
    "10_000 updates and 4 nodes" => setup.(4, 10_000),
    "10_000 updates and 8 nodes" => setup.(8, 10_000)
  },
  before_each: fn {nodes, size, values} ->
    stop_slaves(nodes)
    wait(fn -> Node.list() != [] end, 500, 20) |> assert("no nodes connected?")

    opts = [
      delta: 10,
      level: 1,
      rounds: nodes + round(nodes / 2)
    ]

    init_slaves(nodes, Support.BenchHandler, opts)
    wait(fn -> !slaves_connected?(nodes) end, 500, 20) |> assert("slaves connected?")

    {nodes, size, values}
  end
)
