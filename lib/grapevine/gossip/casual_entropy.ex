defmodule Grapevine.Gossip.CasualEntropy do
  @moduledoc false

  use Grapevine.Gossip

  require Logger

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def do_init(state, opts) do
    state = %{ state |
      self: self(),
      crdt: crdt_module().new(Node.self()),
      deltas: Map.new(),
      acks: Map.new(),
      sequence: 0,
      ship_interval: Keyword.get(opts, :ship_interval, 1000),
      gc_interval: Keyword.get(opts, :gc_interval, 1000),
      node: Keyword.get(opts, :membership_module, membership()),
      storage: Keyword.get(opts, :storage_module, storage())
    }

    node = state.node.self()
    {:ok, _} = state.storage.init(id: node)

    state =
      case state.storage.read(node) do
        {:ok, []} ->
          state

        {:ok, result} ->
          Map.merge(state, Keyword.get(result, node, %{}))
      end

    gc(self(), state.gc_interval)
    {:ok, state}
  end

  def inc(delta), do: GenServer.call(__MODULE__, {:inc, delta})

  def handle_call(
        {:inc, n},
        _from,
        %{crdt: crdt, deltas: deltas, sequence: seq, node: node} = state
      ) do
    {crdt, delta} = crdt_module().inc(crdt, n)

    new_state =
      state
      |> Map.put(:crdt, crdt)
      |> Map.put(:deltas, Map.put(deltas, seq, %{delta: delta}))
      |> Map.put(:sequence, seq + 1)

    store(node.self(), new_state)

    {:reply, :ok, new_state}
  end

  def handle_info(:ship, %{self: pid, ship_interval: interval} = state) do
    j = neighbours(state)

    if !acked?(j, state), do: send_to_neighbour(j, state)

    period(pid, interval)
    {:noreply, state}
  end

  def neighbours(%{node: node}), do: node.list() |> random()

  def handle_info(:gc, %{self: pid, gc_interval: gc_interval, node: node, acks: acks} = state) do
    deltas =
      node.list()
      |> Enum.map(fn n -> Map.get(acks, ref(__MODULE__, n), 0) end)
      |> gc_deltas(state)

    gc(pid, gc_interval)
    {:noreply, %{state | deltas: deltas}}
  end

  def handle_info(
        {:receive, from, {received_deltas, n}},
        %{deltas: deltas, crdt: crdt, node: node, sequence: seq} = state
      ) do
    if !merged?(from, received_deltas, crdt) do
      new_state =
        state
        |> Map.put(:crdt, merge_deltas(crdt, received_deltas))
        |> Map.put(:deltas, Map.put(deltas, seq, received_deltas))
        |> Map.put(:sequence, seq + 1)

      node = node.self()
      store(node, new_state)

      send_ack(from, node, n)
      {:noreply, new_state}
    else
      send_ack(from, node.self(), n)
      {:noreply, state}
    end
  end

  def handle_info({:ack, from, sequence}, %{acks: acks} = state),
    do: {:noreply, %{state | acks: Map.put(acks, from, Map.get(acks, from, 0) |> max(sequence))}}

  defp gc_deltas(acks, %{deltas: deltas}) when acks == [], do: deltas
  defp gc_deltas(_, %{deltas: deltas, acks: acks}) when acks == %{}, do: deltas

  defp gc_deltas(acks, %{deltas: deltas}) do
    min_seq = Enum.min(acks)
    Enum.filter(deltas, fn {k, _d} -> k >= min_seq end) |> Map.new()
  end

  defp acked?(j, %{acks: acks, sequence: seq}), do: Map.get(acks, ref(__MODULE__, j), 0) >= seq

  defp send_ack(to, from, n), do: send(to, {:ack, ref(__MODULE__, from), n})

  defp random(nodes), do: Enum.shuffle(nodes) |> List.first()

  defp merged?(node, %{delta: %{payload: delta}}, %{payload: crdt}) do
    neighbour = get_ref(node)
    Map.get(crdt, neighbour, 0) >= Map.get(delta, neighbour, 0)
  end

  defp no_deltas?(%{deltas: deltas}) when deltas == %{}, do: true
  defp no_deltas?(_), do: false

  defp missing_delta?(j, %{deltas: deltas, acks: acks}),
    do: Map.keys(deltas) |> Enum.min() > Map.get(acks, ref(__MODULE__, j), 0)

  defp send_to_neighbour(neighbour, state) do
    if no_deltas?(state) || missing_delta?(neighbour, state),
      do: send_full_state(neighbour, state),
      else: send_delta_interval(neighbour, state)
  end

  defp send_full_state(neighbour, %{crdt: crdt, node: node, sequence: seq}),
    do: do_send(neighbour, node.self(), {%{delta: crdt, type: :full_state}, seq})

  defp send_delta_interval(neighbour, %{
         deltas: deltas,
         acks: acks,
         node: node,
         sequence: seq
       }) do
    acked = Map.get(acks, ref(__MODULE__, neighbour), 0)

    delta =
      deltas
      |> Enum.filter(fn {k, _v} -> acked <= k && k < seq end)
      |> Enum.reduce(crdt_module().new(node.self()), fn {_k, %{delta: delta}}, crdt ->
        crdt_module().merge(crdt, delta)
      end)

    do_send(neighbour, node.self(), {%{delta: delta, type: :delta_interval}, seq})
  end

  defp merge_deltas(crdt, %{delta: delta}), do: crdt_module().merge(crdt, delta)

  defp do_send(node, from, message),
    do: send(ref(__MODULE__, node), {:receive, ref(__MODULE__, from), message})

  defp ref(_ref, node) when is_pid(node), do: node
  defp ref(ref, node), do: {ref, node}

  defp get_ref({_module, node}), do: node
  defp get_ref(node), do: node

  defp store(node, %{crdt: crdt, sequence: seq, storage: storage}),
    do: :ok = storage.write(node, %{sequence: seq, crdt: crdt})

  defp period(pid, interval), do: Process.send_after(pid, :ship, interval)

  defp gc(pid, interval), do: Process.send_after(pid, :gc, interval)

  defp crdt_module(), do: Application.get_env(:grapevine, :crdt_module)

  defp membership(), do: Application.get_env(:grapevine, :membership_module)

  defp storage(), do: Application.get_env(:grapevine, :storage_module)
end
