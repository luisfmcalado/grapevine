defmodule Grapevine.NodeTest do
  use ExUnit.Case
  doctest Grapevine.Node

  import Grapevine.Support.Cluster

  alias Grapevine.Node
  alias Grapevine.Gossip.Rumor

  setup do
    Process.flag(:trap_exit, true)

    setup_distributed()
    init_slaves(3, Rumor)

    {:ok, pid} = Node.start_link(mfa: {Grapevine.NodeTest, :add, [self()]})

    on_exit(fn ->
      stop_slaves(3)

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, _, _, _}
    end)

    {:ok, pid: pid}
  end

  test "it detects when a node goes down", %{pid: _pid} do
    stop_slave(1)
    assert_receive {self, %{action: :nodedown, node: :slave_1@localhost}}, 1000
  end

  test "it detects when a node goes up", %{pid: _pid} do
    start_slave(3, Rumor)
    assert_receive {self, %{action: :nodeup, node: :slave_3@localhost}}, 1000
  end

  test "it returns a list of nodes" do
    assert [:slave_0@localhost, :slave_1@localhost, :slave_2@localhost] == Node.list()
  end

  test "it returns the node name" do
    assert :master@localhost == Node.self()
  end

  def add(name, _id, value) do
    send(name, {name, value})
  end
end
