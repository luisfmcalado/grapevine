defmodule Grapevine.Gossip do
  @moduledoc """
  This module is the interface for custom gossip protocols

  The module implements basic behaviour for a gossip protocol
  """

  @callback do_init(map(), keyword()) :: {:ok, map()}
  @callback push(map(), pid(), map()) :: map()
  @callback filter(map()) :: map()
  @callback neighbours(map()) :: [node, ...]
  @callback merge(binary(), any(), map()) :: map()

  @spec add(atom(), binary(), any(), non_neg_integer()) :: :ok | {:error, term()}
  def add(name, id, value, timeout \\ 5000) do
    GenServer.call(name, {:add, id, value}, timeout)
  end

  defmacro __using__(_) do
    quote do
      @behaviour Grapevine.Gossip

      use GenServer

      def start_link(handler, opts) do
        GenServer.start_link(__MODULE__, [handler, opts],
          name: Keyword.get(opts, :name, __MODULE__)
        )
      end

      def init([handler, opts]) do
        state = %{
          self: self(),
          handler: handler,
          updates: Map.new(),
          delta: Keyword.get(opts, :delta, 500),
          name: Keyword.get(opts, :name, __MODULE__),
          membership_module: Keyword.fetch!(opts, :membership_module)
        }

        delta(state.self)
        do_init(state, opts)
      end

      def child_spec([handler, opts]) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [handler, opts]},
          restart: :permanent,
          type: :worker
        }
      end

      def handle_call({:add, id, value}, _from, %{updates: updates} = state) do
        state = Map.merge(state, merge(id, value, state))
        {:reply, :ok, state}
      end

      def handle_info(:delta, %{self: pid, delta: delta} = state) do
        do_gossip(state)
        delta(pid, delta)
        {:noreply, state}
      end

      def handle_info({:push, from, updates}, state) do
        state = Map.merge(state, push(updates, from, state))
        {:noreply, state}
      end

      defp do_gossip(state) do
        neighbours(state)
        |> gossip_to_neighbours(state, filter(state) |> values())
      end

      defp gossip_to_neighbours([], _, _, _), do: :ignore
      defp gossip_to_neighbours(_, _, _, []), do: :ignore

      defp gossip_to_neighbours(nodes, %{name: name, membership_module: msm}, updates) do
        self_ref = ref(name, msm.self())
        Enum.each(nodes, &send(ref(name, &1), {:push, self_ref, updates}))
      end

      defp ref(ref, _node) when is_pid(ref), do: ref
      defp ref(ref, node) when is_atom(ref), do: {ref, node}

      defp delta(pid, timeout \\ 0), do: Process.send_after(pid, :delta, timeout)

      defp values(updates) do
        Enum.map(updates, fn {k, %{value: value}} -> {k, value} end)
      end
    end
  end
end
