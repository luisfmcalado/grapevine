defmodule Grapevine.CasualEntropyTest do
  use ExUnit.Case, async: true

  import Mox

  alias Grapevine.Gossip.CasualEntropy

  @moduletag :e1
  @id :replica1

  describe "when the causal entropy starts" do
    test "it loads the state form storage" do
      Grapevine.StorageMock
      |> expect(:init, 1, fn _ -> {:ok, self()} end)
      |> expect(:read, 1, fn _ -> {:ok, []} end)

      CasualEntropy.init(storage_module: Grapevine.StorageMock)
    end
  end

  describe "when the ship interval is triggered" do
    test "it sends the full state if the deltas are empty" do
      Grapevine.MembershipMock
      |> expect(:list, 1, fn -> [self(), self()] end)
      |> expect(:self, 2, fn -> @id end)

      {crdt, _d1} = crdt_module().new(@id) |> crdt_module().inc(1)
      state = state(%{crdt: crdt, deltas: %{}, sequence: 1})
      {:noreply, %{crdt: crdt}} = CasualEntropy.handle_info(:ship, state)

      delta_interval = delta_interval(crdt, :full_state)

      assert_receive {:receive, _, {^delta_interval, 1}}
    end

    test "it does not send delta/state if the sequence was acked" do
      Grapevine.MembershipMock
      |> expect(:list, 1, fn -> [self()] end)

      {crdt, _d1} = crdt_module().new(@id) |> crdt_module().inc(1)
      {crdt, d2} = crdt_module().inc(crdt, 1)

      deltas = %{1 => delta(d2)}
      acks = %{self() => 2}
      state = state(%{crdt: crdt, deltas: deltas, sequence: 2, acks: acks})
      {:noreply, %{crdt: crdt}} = CasualEntropy.handle_info(:ship, state)

      refute_receive {:receive, _, {^crdt, :full}}
    end

    test "it sends the full state if the delta is missing" do
      Grapevine.MembershipMock
      |> expect(:list, 1, fn -> [self()] end)
      |> expect(:self, 1, fn -> @id end)

      {crdt, _d1} = crdt_module().new(@id) |> crdt_module().inc(1)
      {crdt, _d2} = crdt_module().inc(crdt, 1)
      {crdt, d3} = crdt_module().inc(crdt, 1)

      deltas = %{3 => delta(d3)}
      acks = %{self() => 2}
      state = state(%{crdt: crdt, deltas: deltas, sequence: 4, acks: acks})
      {:noreply, %{crdt: crdt}} = CasualEntropy.handle_info(:ship, state)

      delta_interval = delta_interval(crdt, :full_state)
      assert_receive {:receive, _, {^delta_interval, 4}}
    end

    test "it sends the delta interval" do
      Grapevine.MembershipMock
      |> expect(:list, 1, fn -> [self()] end)
      |> expect(:self, 2, fn -> @id end)

      crdt = crdt_module().new(@id)
      {crdt, d1} = crdt_module().inc(crdt, 1)
      {crdt, d2} = crdt_module().inc(crdt, 2)
      {crdt, d3} = crdt_module().inc(crdt, 3)

      deltas = %{
        0 => delta(d1),
        1 => delta(d2),
        2 => delta(d3)
      }

      delta_interval =
        deltas
        |> Map.drop([0])
        |> Enum.reduce(crdt_module().new(@id), fn {_k, %{delta: d}}, acc ->
          crdt_module().merge(acc, d)
        end)
        |> delta_interval()

      acks = %{self() => 1}
      state = state(%{crdt: crdt, deltas: deltas, sequence: 3, acks: acks})
      CasualEntropy.handle_info(:ship, state)

      assert_receive {:receive, _, {^delta_interval, 3}}
    end
  end

  describe "when the garbage collection is triggered" do
    test "it removes the deltas acked by all nodes" do
      Grapevine.MembershipMock
      |> expect(:list, 1, fn -> [self(), :node_1] end)

      crdt = crdt_module().new(@id)
      {crdt, d1} = crdt_module().inc(crdt, 1)
      {crdt, d2} = crdt_module().inc(crdt, 2)
      {crdt, d3} = crdt_module().inc(crdt, 3)

      deltas = %{
        0 => delta(d1),
        1 => delta(d2),
        2 => delta(d3)
      }

      acks = %{{CasualEntropy, :node_1} => 1, self() => 2}
      state = state(%{crdt: crdt, deltas: deltas, sequence: 3, acks: acks})
      {:noreply, %{deltas: updated_deltas}} = CasualEntropy.handle_info(:gc, state)

      assert Map.drop(deltas, [0]) == updated_deltas
    end

    test "it requests for the next garbage collection" do
      Grapevine.MembershipMock
      |> expect(:list, 1, fn -> [self()] end)

      CasualEntropy.handle_info(:gc, default_state())
      assert_receive :gc
    end
  end

  describe "when an ack is received" do
    test "the ack is updated with higher sequence" do
      crdt = crdt_module().new(@id)
      acks = %{:node_id => 1}
      state = state(%{crdt: crdt, sequence: 3, acks: acks})
      {:noreply, %{acks: acks}} = CasualEntropy.handle_info({:ack, :node_id, 2}, state)

      assert %{:node_id => 2} == acks
    end

    test "the ack sequence is kept lower" do
      crdt = crdt_module().new(@id)
      acks = %{:node_id => 2}
      state = state(%{crdt: crdt, sequence: 3, acks: acks})
      {:noreply, %{acks: acks}} = CasualEntropy.handle_info({:ack, :node_id, 1}, state)

      assert %{:node_id => 2} == acks
    end
  end

  describe "when an operation is done" do
    test "it increments the sequence number" do
      Grapevine.MembershipMock
      |> expect(:self, 1, fn -> @id end)

      Grapevine.StorageMock
      |> expect(:write, 1, fn _, _ -> :ok end)

      {:reply, :ok, %{sequence: seq}} =
        CasualEntropy.handle_call({:inc, 2}, self(), default_state())

      assert seq == 1
    end

    test "it joins the delta mutation into the crdt state" do
      Grapevine.MembershipMock
      |> expect(:self, 1, fn -> @id end)

      Grapevine.StorageMock
      |> expect(:write, 1, fn _, _ -> :ok end)

      {:reply, :ok, %{crdt: crdt}} = CasualEntropy.handle_call({:inc, 3}, self(), default_state())
      {c, _d} = crdt_module().new(@id) |> crdt_module().inc(3)

      assert crdt == c
    end

    test "it joins the delta mutation into the deltas" do
      Grapevine.MembershipMock
      |> expect(:self, 2, fn -> @id end)

      Grapevine.StorageMock
      |> expect(:write, 2, fn _, _ -> :ok end)

      {:reply, :ok, state} = CasualEntropy.handle_call({:inc, 3}, self(), default_state())
      {:reply, :ok, %{deltas: deltas}} = CasualEntropy.handle_call({:inc, 4}, self(), state)

      crdt = crdt_module().new(@id)
      {crdt, d1} = crdt_module().inc(crdt, 3)
      {_crdt, d2} = crdt_module().inc(crdt, 4)

      crdt_deltas = %{0 => delta(d1), 1 => delta(d2)}
      assert crdt_deltas == deltas
    end
  end

  describe "when receives a delta interval" do
    test "it joins the delta interval into the deltas" do
      Grapevine.MembershipMock
      |> expect(:self, 1, fn -> self() end)

      Grapevine.StorageMock
      |> expect(:write, 1, fn _, _ -> :ok end)

      {_c, d} = crdt_module().new(self()) |> gen_deltas(0, 0)
      delta_interval = merge_deltas(d, 1, @id)

      {:noreply, %{deltas: deltas}} =
        CasualEntropy.handle_info({:receive, self(), {delta_interval, 1}}, default_state())

      assert %{0 => delta_interval} == deltas
    end

    test "it joins the delta interval into the crdt state" do
      Grapevine.MembershipMock
      |> expect(:self, 1, fn -> self() end)

      Grapevine.StorageMock
      |> expect(:write, 1, fn _, _ -> :ok end)

      {gen_crdt, delta} = crdt_module().new(self()) |> gen_deltas(0, 0)
      delta_interval = merge_deltas(delta, 1, self())

      state = state(%{crdt: crdt_module().new(self())})

      {:noreply, %{crdt: crdt}} =
        CasualEntropy.handle_info({:receive, self(), {delta_interval, 1}}, state)

      assert gen_crdt == crdt
    end

    test "it increments the sequence number" do
      Grapevine.MembershipMock
      |> expect(:self, 1, fn -> self() end)

      Grapevine.StorageMock
      |> expect(:write, 1, fn _, _ -> :ok end)

      {_c, delta} = crdt_module().new(self()) |> gen_deltas(0, 0)
      delta_interval = merge_deltas(delta, 1, @id)

      {:noreply, %{sequence: sequence}} =
        CasualEntropy.handle_info({:receive, self(), {delta_interval, 1}}, default_state())

      assert sequence == 1
    end

    test "it ignores merged deltas" do
      Grapevine.MembershipMock
      |> expect(:self, 1, fn -> @id end)

      {_c, delta} = crdt_module().new(@id) |> gen_deltas(0, 3)
      delta_interval = merge_deltas(delta, 4, @id)

      {gen_crdt, _delta} = crdt_module().new(@id) |> gen_deltas(0, 4)
      state = state(%{crdt: gen_crdt, sequence: 5, casual_order: %{self() => 4}})

      {:noreply, %{crdt: crdt, sequence: seq}} =
        CasualEntropy.handle_info({:receive, self(), {delta_interval, 3}}, state)

      assert seq == 5
      assert gen_crdt == crdt
    end

    test "it sends the ack for the sequence number received when ignored" do
      Grapevine.MembershipMock
      |> expect(:self, 1, fn -> @id end)

      {_c, delta} = crdt_module().new(@id) |> gen_deltas(3, 4)
      delta_interval = merge_deltas(delta, 5, @id)

      {gen_crdt, _delta} = crdt_module().new(@id) |> gen_deltas(0, 0)
      state = state(%{acks: %{self() => 1}, crdt: gen_crdt})
      CasualEntropy.handle_info({:receive, self(), {delta_interval, 5}}, state)

      assert_receive {:ack, _, 5}
    end

    test "it sends the ack for the sequence number received" do
      Grapevine.MembershipMock
      |> expect(:self, 1, fn -> @id end)

      {_c, delta} = crdt_module().new(@id) |> gen_deltas(0, 4)
      delta_interval = merge_deltas(delta, 5, @id)

      CasualEntropy.handle_info({:receive, self(), {delta_interval, 5}}, default_state())

      assert_receive {:ack, _, 5}
    end
  end

  defp default_state(),
    do: %{
      self: self(),
      crdt: crdt_module().new(@id),
      deltas: %{},
      acks: %{},
      sequence: 0,
      ship_interval: 500,
      gc_interval: 10,
      node: Grapevine.MembershipMock,
      storage: Grapevine.StorageMock
    }

  defp state(state), do: Map.merge(default_state(), state)

  defp merge_deltas(deltas, seq, id) do
    deltas
    |> Enum.filter(fn {k, _v} -> k < seq end)
    |> Enum.reduce(crdt_module().new(id), fn {_k, %{delta: d}}, acc ->
      crdt_module().merge(acc, d)
    end)
    |> delta_interval()
  end

  defp gen_deltas(crdt, a, b) do
    Enum.reduce(a..b, {crdt, Map.new()}, fn n, {crdt, m} ->
      {crdt, d} = crdt_module().inc(crdt)
      {crdt, Map.put(m, n, delta(d))}
    end)
  end

  defp delta_interval(delta, type \\ :delta_interval),
    do: %{delta: delta, type: type}

  defp delta(val), do: %{delta: val}

  defp crdt_module, do: Application.get_env(:grapevine, :crdt_module)
end
