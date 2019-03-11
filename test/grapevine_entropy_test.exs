defmodule GrapevineEntropyTest do
  use ExUnit.Case
  doctest Grapevine

  import Grapevine.Support.Cluster
  import Grapevine.Support.Wait

  alias Grapevine.Support.DummyHandler
  alias Grapevine.Gossip.Entropy

  @number_of_slaves 2
  @name :gsp_entropy_1
  setup do
    opts = [
      name: @name,
      membership_module: Grapevine.Node,
      membership_opts: [
        mfa: {Grapevine, :add, [@name]}
      ]
    ]

    {:ok, pid} = Grapevine.start_link(Entropy, DummyHandler, opts)

    on_exit(fn ->
      stop_slaves(@number_of_slaves)
      stop_master()

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, _, _, _}
    end)
  end

  test "it starts the gossip" do
    assert true == Process.alive?(Process.whereis(@name))
  end

  test "it gossip the state between nodes" do
    setup_distributed()

    init_slaves(@number_of_slaves, Entropy, DummyHandler, name: @name)
    assert true == wait(fn -> !slaves_connected?(@number_of_slaves) end, 500, 30)
    assert true == wait(fn -> !master_sync?(@number_of_slaves + 1) end, 500, 30)
    assert true == wait(fn -> !in_sync?(@number_of_slaves, 0) end, 500, 30)

    Grapevine.add(@name, "id1", %{id: 1})
    assert true == wait(fn -> !master_sync?(@number_of_slaves + 2) end, 500, 30)
    assert true == wait(fn -> !in_sync?(@number_of_slaves, 1) end, 500, 30)
  end

  defp master_sync?(n) do
    %{updates: updates} = :sys.get_state(Process.whereis(@name))
    Enum.count(updates) == n
  end

  defp in_sync?(n, size) do
    %{updates: master_updates} = :sys.get_state(Process.whereis(@name))

    Enum.all?(0..(n - 1), fn i ->
      %{updates: updates} =
        :rpc.block_call(:"slave_#{i}@localhost", Process, :whereis, [@name])
        |> :sys.get_state()

      Map.keys(updates) == Map.keys(master_updates) && Enum.count(updates) == size + n + 1
    end)
  end
end
