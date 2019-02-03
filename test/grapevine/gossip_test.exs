defmodule Grapevine.GossipTest do
  use ExUnit.Case
  doctest Grapevine.Gossip

  import Mox

  setup :verify_on_exit!

  alias Grapevine.Gossip
  alias Grapevine.{Message, Updates}
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
    updates: Updates.new(),
    membership_module: MembershipMock,
    rounds: @rounds,
    level: 2
  }

  test "it adds the update to the state" do
    {_, _, %{updates: updates}} = Gossip.handle_call({:add, %{id: 1}}, self(), @state)

    assert %{
             "A7B5AB89427571BAF5D2D937C5E986DC" => %Message{
               value: %{id: 1},
               rounds: 2,
               state: :infected
             }
           } == updates
  end

  test "it triggers the delta on init" do
    Gossip.init([GossipHandler, [delta: 1000, membership_module: MembershipMock]])
    assert_receive :delta
  end

  test "it triggers the gc on init" do
    Gossip.init([GossipHandler, [gc: 0, membership_module: MembershipMock]])
    assert_receive :gc
  end

  test "it triggers the delta every interval" do
    Grapevine.MembershipMock
    |> expect(:list, 1, fn -> [] end)
    |> expect(:self, 1, fn -> Node.self() end)

    state = Map.merge(@state, %{self: self()})
    Gossip.handle_info(:delta, state)
    assert_receive :delta, 1100
  end

  test "it send a initialized message on init" do
    Gossip.init([GossipHandler, [membership_module: MembershipMock]])
    assert_receive :initialized
  end

  test "it send a message of gossip process initialized" do
    Grapevine.MembershipMock
    |> expect(:self, 1, fn -> :node@nohost end)

    {:noreply, %{updates: updates}} = Gossip.handle_info(:initialized, @state)

    assert %{
             "73907136EA1E109AD941936CB4B99802" => %Message{
               rounds: 2,
               state: :infected,
               value: %{node: :node@nohost, action: :initialized}
             }
           } == updates
  end

  test "it triggers the garbage collect every interval" do
    state = Map.merge(@state, %{self: self()})
    Gossip.handle_info(:gc, state)
    assert_receive :gc, 1100
  end

  test "it sends feedback when a push request is executed" do
    HandlerMock
    |> expect(:push, fn _n, _u -> :ok end)

    updates =
      Updates.new()
      |> Updates.add(%{value: 1000}, @rounds)
      |> Updates.add(%{value: 2000}, @rounds)

    new_updates = [%{value: 1}, %{value: 2000}]
    state = Map.merge(@state, %{updates: updates})

    Gossip.handle_info({:push, self(), new_updates}, state)
    assert_receive {:feedback, ["01DCFBD18A442F09E2B5169DD1AF2B04"]}
  end

  test "it returns the child spec" do
    assert %{
             id: Grapevine.Gossip,
             start: {Grapevine.Gossip, :start_link, [HandlerMock, [name: :gsp1]]},
             restart: :permanent,
             type: :worker
           } == Gossip.child_spec([HandlerMock, [name: :gsp1]])
  end

  test "it sends the value to node" do
    Grapevine.MembershipMock
    |> expect(:list, 1, fn -> [Node.self()] end)
    |> expect(:self, 1, fn -> Node.self() end)

    updates =
      Updates.new()
      |> Updates.add(%{value: 1000}, @rounds)

    new_updates = [%{value: 1000}]

    state =
      Map.merge(@state, %{
        self: self(),
        name: self(),
        updates: updates
      })

    Gossip.handle_info(:delta, state)
    assert_receive {:push, _, ^new_updates}, 1500
  end

  test "it adds new updates to the state" do
    HandlerMock
    |> expect(:push, fn _n, _u -> :ok end)

    updates =
      Updates.new()
      |> Updates.add(%{value: 1000}, @rounds)

    new_updates = [%{value: 2000}]
    state = Map.merge(@state, %{updates: updates})

    {:noreply, %{updates: updates}} = Gossip.handle_info({:push, self(), new_updates}, state)

    assert %{
             "01DCFBD18A442F09E2B5169DD1AF2B04" => %Message{
               rounds: 2,
               state: :infected,
               value: %{value: 2000}
             },
             "5A56CFDB0BBE839A906BFF322CA2EB56" => %Message{
               rounds: 2,
               state: :infected,
               value: %{value: 1000}
             }
           } == updates
  end

  test "it marks has removed when the rounds end" do
    updates =
      Updates.new()
      |> Updates.add(%{value: 1000}, 1)

    known_updates = ["5A56CFDB0BBE839A906BFF322CA2EB56"]

    state =
      Map.merge(@state, %{
        updates: updates
      })

    {:noreply, %{updates: updates}} = Gossip.handle_info({:feedback, known_updates}, state)

    assert %{
             "5A56CFDB0BBE839A906BFF322CA2EB56" => %Message{
               rounds: 0,
               state: :removed,
               value: %{value: 1000}
             }
           } = updates
  end

  test "it counts the number of rounds" do
    updates =
      Updates.new()
      |> Updates.add(%{value: 1000}, 2)

    known_updates = ["5A56CFDB0BBE839A906BFF322CA2EB56"]
    state = Map.merge(@state, %{updates: updates})

    {:noreply, %{updates: updates}} = Gossip.handle_info({:feedback, known_updates}, state)

    assert %{
             "5A56CFDB0BBE839A906BFF322CA2EB56" => %Message{
               rounds: 1,
               state: :infected,
               value: %{value: 1000}
             }
           } == updates
  end

  test "it removes expired updates" do
    updates = %{
      "5A56CFDB0BBE839A906BFF322CA2EB56" => %Message{
        rounds: 0,
        state: :removed_at,
        removed_at: 1_550_045_863,
        value: %{value: 1000}
      }
    }

    state = Map.merge(@state, %{updates: updates})
    {:noreply, %{updates: updates}} = Gossip.handle_info(:gc, state)

    assert %{} == updates
  end

  test "it ignores the updates when the handler returns ignore" do
    HandlerMock
    |> expect(:push, fn _n, _u -> :ignore end)

    updates =
      Updates.new()
      |> Updates.add(%{value: 1000}, @rounds)

    new_updates = [%{value: 2000}]
    state = Map.merge(@state, %{updates: updates})

    {:noreply, %{updates: updates}} = Gossip.handle_info({:push, self(), new_updates}, state)

    assert %{
             "5A56CFDB0BBE839A906BFF322CA2EB56" => %Message{
               rounds: 2,
               state: :infected,
               value: %{value: 1000}
             }
           } == updates
  end

  test "it ignores the updates when filtered by the handler" do
    HandlerMock
    |> expect(:push, fn _n, _u -> {:ok, [%{value: 2000}]} end)

    updates =
      Updates.new()
      |> Updates.add(%{value: 1000}, @rounds)

    new_updates = [%{value: 3000}, %{value: 2000}]
    state = Map.merge(@state, %{updates: updates})

    {:noreply, %{updates: updates}} = Gossip.handle_info({:push, self(), new_updates}, state)

    assert %{
             "5A56CFDB0BBE839A906BFF322CA2EB56" => %Message{
               rounds: 2,
               state: :infected,
               value: %{value: 1000}
             },
             "01DCFBD18A442F09E2B5169DD1AF2B04" => %Message{
               removed_at: nil,
               rounds: 2,
               state: :infected,
               value: %{value: 2000}
             }
           } == updates
  end
end
