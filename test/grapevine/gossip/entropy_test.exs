defmodule Grapevine.Gossip.EntropyTest do
  use ExUnit.Case
  doctest Grapevine.Gossip.Entropy

  import Mox

  setup :verify_on_exit!

  alias Grapevine.Gossip.Entropy
  alias Grapevine.HandlerMock
  alias Grapevine.MembershipMock

  @state %{
    self: self(),
    name: __MODULE__,
    handler: HandlerMock,
    delta: 1000,
    updates: %{},
    membership_module: MembershipMock
  }

  test "it adds the update to the state" do
    {_, _, %{updates: updates}} = Entropy.handle_call({:add, "id1", %{id: 1}}, self(), @state)
    assert %{"id1" => %{value: %{id: 1}}} == updates
  end

  test "it triggers the delta on init" do
    Entropy.init([GossipHandler, [delta: 1000, membership_module: MembershipMock]])
    assert_receive :delta
  end

  test "it triggers the delta every interval" do
    Grapevine.MembershipMock
    |> expect(:list, 1, fn -> [] end)
    |> expect(:self, 1, fn -> Node.self() end)

    state = Map.merge(@state, %{self: self()})
    Entropy.handle_info(:delta, state)
    assert_receive :delta, 1100
  end

  test "it returns the child spec" do
    assert %{
             id: Grapevine.Gossip.Entropy,
             start: {Grapevine.Gossip.Entropy, :start_link, [HandlerMock, [name: :gsp1]]},
             restart: :permanent,
             type: :worker
           } == Entropy.child_spec([HandlerMock, [name: :gsp1]])
  end

  test "it sends the value to all nodes" do
    Grapevine.MembershipMock
    |> expect(:list, 1, fn -> [Node.self(), Node.self()] end)
    |> expect(:self, 1, fn -> Node.self() end)

    updates = new_update("id1", 1000)

    state =
      Map.merge(@state, %{
        self: self(),
        name: self(),
        updates: updates
      })

    Entropy.handle_info(:delta, state)
    assert_receive {:push, _, [{"id1", 1000}]}, 1500
    assert_receive {:push, _, [{"id1", 1000}]}, 1500
  end

  test "it adds new updates to the state" do
    HandlerMock
    |> expect(:push, fn _n, _u -> :ok end)

    updates = new_update("id1", 1000)
    state = Map.merge(@state, %{updates: updates})
    new_updates = [{"id2", 2000}]

    {:noreply, %{updates: updates}} = Entropy.handle_info({:push, self(), new_updates}, state)

    assert %{
             "id2" => %{value: 2000},
             "id1" => %{value: 1000}
           } == updates
  end

  test "it ignores the updates when the handler returns ignore" do
    HandlerMock
    |> expect(:push, fn _n, _u -> :ignore end)

    updates = new_update("id1", 1000)
    state = Map.merge(@state, %{updates: updates})
    new_updates = [{"id2", %{value: 2000}}]

    {:noreply, %{updates: updates}} = Entropy.handle_info({:push, self(), new_updates}, state)

    assert %{
             "id1" => %{value: 1000}
           } == updates
  end

  test "it ignores the updates when filtered by the handler" do
    HandlerMock
    |> expect(:push, fn _n, _u -> {:ok, new_update("id3", 2000)} end)

    updates = new_update("id1", 1000)
    state = Map.merge(@state, %{updates: updates})
    new_updates = [{"id2", 3000}, {"id3", 2000}]

    {:noreply, %{updates: updates}} = Entropy.handle_info({:push, self(), new_updates}, state)

    assert %{
             "id1" => %{value: 1000},
             "id3" => %{value: 2000}
           } == updates
  end

  test "it resets the updates" do
    HandlerMock
    |> expect(:push, fn _n, _u -> {:reset, new_update("id3", 2000)} end)

    updates = new_update("id1", 1000)
    state = Map.merge(@state, %{updates: updates})
    new_updates = [{"id2", %{value: 3000}}, {"id3", %{value: 2000}}]

    {:noreply, %{updates: updates}} = Entropy.handle_info({:push, self(), new_updates}, state)
    assert %{"id3" => %{value: 2000}} == updates
  end

  test "it overwrites existing updates" do
    updates = new_update("id1", 1000)
    state = Map.merge(@state, %{updates: updates})
    %{updates: updates} = Entropy.merge("id1", 2000, state)

    assert %{"id1" => %{value: 2000}} == updates
  end

  test "it overwrites received updates" do
    HandlerMock
    |> expect(:push, fn _n, _u -> :ok end)

    updates = new_update("id1", 1000)
    state = Map.merge(@state, %{updates: updates})
    new_updates = [{"id1", 2000}]

    {:noreply, %{updates: updates}} = Entropy.handle_info({:push, self(), new_updates}, state)
    assert %{"id1" => %{value: 2000}} == updates
  end

  defp new_update(id, value), do: %{id => %{value: value}}
end
