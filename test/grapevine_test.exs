defmodule GrapevineTest do
  use ExUnit.Case
  doctest Grapevine

  import Mox
  import Grapevine.Support.Cluster
  import Grapevine.Support.Wait

  setup :verify_on_exit!

  alias Grapevine.Support.DummyHandler

  setup do
    opts = [
      name: :gsp1,
      membership_module: Grapevine.Node,
      membership_opts: [
        mfa: {Grapevine, :add, [:gsp1]}
      ]
    ]

    {:ok, pid} = Grapevine.start_link(DummyHandler, opts)

    on_exit(fn ->
      stop_slaves(2)

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, _, _, _}
    end)
  end

  test "it starts the gossip" do
    assert true == Process.alive?(Process.whereis(:gsp1))
  end

  test "it gossip the state between nodes" do
    setup_distributed()

    slave_size = 2
    init_slaves(slave_size)
    assert true == wait(fn -> !slaves_connected?(slave_size) end, 500, 30)
    assert true == wait(fn -> !master_sync?(slave_size + 4) end, 500, 30)
    assert true == wait(fn -> !in_sync?(slave_size, 0) end, 500, 30)

    Grapevine.add(:gsp1, %{id: 1})
    assert true == wait(fn -> !master_sync?(slave_size + 5) end, 500, 30)
    assert true == wait(fn -> !in_sync?(slave_size, 1) end, 500, 30)
  end

  defp master_sync?(n) do
    %{updates: updates} = :sys.get_state(Process.whereis(:gsp1))
    Enum.count(updates, fn {_k, %{state: state}} -> state == :removed end) == n
  end

  defp in_sync?(n, size) do
    %{updates: master_updates} = :sys.get_state(Process.whereis(:gsp1))

    Enum.all?(0..(n - 1), fn i ->
      %{updates: updates} =
        :rpc.block_call(:"slave_#{i}@localhost", Process, :whereis, [:gsp1])
        |> :sys.get_state()

      Map.keys(updates) == Map.keys(master_updates) &&
        Enum.count(updates, fn {_k, %{state: state}} -> state != :removed end) == 0 &&
        Enum.count(updates, fn {_k, %{state: state}} -> state == :removed end) == size + n + 4
    end)
  end
end
