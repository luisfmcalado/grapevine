defmodule Grapevine.Gossip.RumorTest do
  use ExUnit.Case
  doctest Grapevine.Gossip.Rumor

  import Mox

  setup :verify_on_exit!

  alias Grapevine.Gossip.Rumor
  alias Grapevine.Gossip.Rumor.State
  alias Grapevine.HandlerMock
  alias Grapevine.MembershipMock

  @rounds 2
  @state %{
    self: self(),
    name: __MODULE__,
    handler: HandlerMock,
    delta: 1000,
    gc: 1000,
    ttl: 3000,
    updates: Map.new(),
    meta: Map.new(),
    membership_module: MembershipMock,
    rounds: @rounds,
    level: 2
  }

  test "it adds the update to the state" do
    {_, _, %{updates: updates}} = Rumor.handle_call({:add, "id1", 1}, self(), @state)
    assert %{"id1" => %{value: 1}} == updates
  end

  test "it triggers the delta on init" do
    Rumor.init([GossipHandler, [delta: 1000, membership_module: MembershipMock]])
    assert_receive :delta
  end

  test "it triggers the gc on init" do
    Rumor.init([GossipHandler, [gc: 0, membership_module: MembershipMock]])
    assert_receive :gc
  end

  test "it does not trigger the gc on init" do
    Rumor.init([GossipHandler, [gc: false, membership_module: MembershipMock]])
    refute_receive :gc
  end

  test "it triggers the delta every interval" do
    Grapevine.MembershipMock
    |> expect(:list, 1, fn -> [] end)
    |> expect(:self, 1, fn -> Node.self() end)

    state = Map.merge(@state, %{self: self()})
    Rumor.handle_info(:delta, state)
    assert_receive :delta, 1100
  end

  test "it send a initialized message on init" do
    Rumor.init([GossipHandler, [membership_module: MembershipMock]])
    assert_receive :initialized
  end

  test "it send a message of gossip process initialized" do
    Grapevine.MembershipMock
    |> expect(:self, 1, fn -> :node@nohost end)

    {:noreply, %{updates: updates}} = Rumor.handle_info(:initialized, @state)

    assert %{
             "73907136EA1E109AD941936CB4B99802" => %{
               value: %{node: :node@nohost, action: :initialized}
             }
           } == updates
  end

  test "it triggers the garbage collect every interval" do
    state = Map.merge(@state, %{self: self()})
    Rumor.handle_info(:gc, state)
    assert_receive :gc, 1100
  end

  test "it sends feedback when a push request is executed" do
    HandlerMock
    |> expect(:push, fn _n, _u -> :ok end)

    updates = %{"id1" => %{value: 1000}, "id2" => %{value: 2000}}
    state = Map.merge(@state, %{updates: updates})
    new_updates = [{"id3", 1}, {"id2", 2000}]

    Rumor.handle_info({:push, self(), new_updates}, state)
    assert_receive {:feedback, ["id2"]}
  end

  test "it returns the child spec" do
    assert %{
             id: Grapevine.Gossip.Rumor,
             start: {Grapevine.Gossip.Rumor, :start_link, [HandlerMock, [name: :gsp1]]},
             restart: :permanent,
             type: :worker
           } == Rumor.child_spec([HandlerMock, [name: :gsp1]])
  end

  test "it sends the value to node" do
    Grapevine.MembershipMock
    |> expect(:list, 1, fn -> [Node.self()] end)
    |> expect(:self, 1, fn -> Node.self() end)

    updates = %{"id2" => %{value: 1000}}
    meta = %{"id2" => %State{state: :infected, rounds: @rounds}}

    state =
      Map.merge(@state, %{
        self: self(),
        name: self(),
        updates: updates,
        meta: meta
      })

    new_updates = [{"id2", 1000}]

    Rumor.handle_info(:delta, state)
    assert_receive {:push, _, ^new_updates}, 1500
  end

  test "it sends the value to all nodes" do
    Grapevine.MembershipMock
    |> expect(:list, 1, fn -> [Node.self(), Node.self()] end)
    |> expect(:self, 1, fn -> Node.self() end)

    updates = %{"id2" => %{value: 1000}}
    meta = %{"id2" => %State{state: :infected, rounds: @rounds}}

    state =
      Map.merge(@state, %{
        self: self(),
        name: self(),
        updates: updates,
        meta: meta,
        level: 0
      })

    new_updates = [{"id2", 1000}]

    Rumor.handle_info(:delta, state)
    assert_receive {:push, _, ^new_updates}, 1500
    assert_receive {:push, _, ^new_updates}, 1500
  end

  test "it adds new updates to the state" do
    HandlerMock
    |> expect(:push, fn _n, _u -> :ok end)

    updates = %{"id1" => %{value: 1000}}
    meta = %{"id1" => %State{state: :infected, rounds: @rounds}}
    state = Map.merge(@state, %{updates: updates, meta: meta})

    new_updates = [{"id2", 2000}]

    {:noreply, %{updates: updates, meta: meta}} =
      Rumor.handle_info({:push, self(), new_updates}, state)

    assert %{
             "id1" => %State{rounds: @rounds, state: :infected},
             "id2" => %State{rounds: @rounds, state: :infected}
           } == meta

    assert %{
             "id2" => %{value: 2000},
             "id1" => %{value: 1000}
           } == updates
  end

  test "it marks has removed when the rounds end" do
    updates = %{"id1" => %{value: 1000}}
    meta = %{"id1" => %State{state: :infected, rounds: @rounds}}
    known_updates = ["id1"]

    state =
      Map.merge(@state, %{
        updates: updates,
        meta: meta
      })

    {:noreply, %{updates: updates}} = Rumor.handle_info({:feedback, known_updates}, state)
    assert %{"id1" => %{value: 1000}} = updates
  end

  test "it counts the number of rounds" do
    updates = %{"id1" => %{value: 1000}}
    meta = %{"id1" => %State{state: :infected, rounds: @rounds}}
    known_updates = ["id1"]

    state =
      Map.merge(@state, %{
        updates: updates,
        meta: meta
      })

    {:noreply, %{updates: updates, meta: meta}} =
      Rumor.handle_info({:feedback, known_updates}, state)

    assert %{"id1" => %{value: 1000}} == updates
    assert %{"id1" => %State{rounds: 1, state: :infected}} == meta
  end

  test "it removes expired updates" do
    updates = %{
      "id1" => %{value: 1000},
      "id2" => %{value: 2000}
    }

    meta = %{
      "id1" => %State{state: :removed, rounds: 0, removed_at: 1_550_045_863},
      "id2" => %State{state: :infected, rounds: 1}
    }

    state = Map.merge(@state, %{updates: updates, meta: meta})

    {:noreply, %{updates: updates, meta: meta}} = Rumor.handle_info(:gc, state)

    assert %{
             "id2" => %State{state: :infected, rounds: 1}
           } == meta

    assert %{
             "id2" => %{value: 2000}
           } == updates
  end

  test "it ignores the updates when the handler returns ignore" do
    HandlerMock
    |> expect(:push, fn _n, _u -> :ignore end)

    updates = %{"id1" => %{value: 1000}}
    meta = %{"id1" => %State{state: :infected, rounds: @rounds}}

    state =
      Map.merge(@state, %{
        updates: updates,
        meta: meta
      })

    new_updates = [{"id2", 2000}]

    {:noreply, %{updates: updates}} = Rumor.handle_info({:push, self(), new_updates}, state)
    assert %{"id1" => %{value: 1000}} == updates
  end

  test "it ignores the updates when filtered by the handler" do
    HandlerMock
    |> expect(:push, fn _n, _u -> {:ok, %{"id2" => %{value: 2000}}} end)

    updates = %{"id1" => %{value: 1000}}
    new_updates = [{"id3", 3000}, {"id2", 2000}]
    state = Map.merge(@state, %{updates: updates})

    {:noreply, %{updates: updates}} = Rumor.handle_info({:push, self(), new_updates}, state)

    assert %{
             "id1" => %{value: 1000},
             "id2" => %{value: 2000}
           } == updates
  end

  test "it resets the updates" do
    HandlerMock
    |> expect(:push, fn _n, _u -> {:reset, %{"id3" => %{value: 2000}}} end)

    updates = %{"id1" => %{value: 1000}}
    new_updates = [{"id3", 3000}, {"id2", 2000}]
    state = Map.merge(@state, %{updates: updates})

    {:noreply, %{updates: updates}} = Rumor.handle_info({:push, self(), new_updates}, state)
    assert %{"id3" => %{value: 2000}} == updates
  end

  test "it overwrites existing updates" do
    updates = %{"id1" => %{value: 1000}}
    meta = %{"id1" => %State{state: :infected, rounds: 1}}
    state = Map.merge(@state, %{updates: updates, meta: meta})

    %{updates: updates, meta: meta} = Rumor.merge("id1", 2000, state)

    assert %{"id1" => %{value: 2000}} == updates
    assert %{"id1" => %State{state: :infected, rounds: @rounds}} == meta
  end

  test "it overwrites received updates" do
    HandlerMock
    |> expect(:push, fn _n, _u -> :ok end)

    updates = %{"id1" => %{value: 1000}}
    meta = %{"id1" => %State{state: :infected, rounds: 1}}
    state = Map.merge(@state, %{updates: updates, meta: meta})

    new_updates = [{"id1", 2000}]

    {:noreply, %{updates: updates, meta: meta}} =
      Rumor.handle_info({:push, self(), new_updates}, state)

    assert %{"id1" => %{value: 2000}} == updates
    assert %{"id1" => %State{state: :infected, rounds: 1}} == meta
  end
end
