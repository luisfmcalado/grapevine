defmodule Grapevine.Gossip do
  @moduledoc false
  use GenServer

  alias Grapevine.Updates

  def start_link(handler, opts) do
    GenServer.start_link(__MODULE__, [handler, opts], name: Keyword.get(opts, :name, __MODULE__))
  end

  def init([handler, opts]) do
    state = %{
      self: self(),
      handler: handler,
      updates: Updates.new(),
      delta: Keyword.get(opts, :delta, 500),
      gc: Keyword.get(opts, :gc, 1000),
      ttl: Keyword.get(opts, :ttl, 30000),
      level: Keyword.get(opts, :level, 1),
      rounds: Keyword.get(opts, :rounds, 3),
      name: Keyword.get(opts, :name, __MODULE__),
      membership_module: Keyword.fetch!(opts, :membership_module)
    }

    delta(state.self)
    gc(state.self)
    initialized(state.self)
    {:ok, state}
  end

  def child_spec([handler, opts]) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [handler, opts]},
      restart: :permanent,
      type: :worker
    }
  end

  def handle_call(
        {:add, value},
        _from,
        %{updates: updates, rounds: rounds} = state
      ) do
    {:reply, :ok, %{state | updates: Updates.add(updates, value, rounds)}}
  end

  def handle_info(:delta, %{self: pid, delta: delta} = state) do
    do_gossip(state)
    delta(pid, delta)
    {:noreply, state}
  end

  def handle_info(
        :gc,
        %{self: pid, updates: updates, gc: timeout, ttl: ttl} = state
      ) do
    gc(pid, timeout)
    {:noreply, %{state | updates: Updates.clean(updates, ttl)}}
  end

  def handle_info(
        :initialized,
        %{membership_module: msm, updates: updates, rounds: rounds} = state
      ) do
    value = %{node: msm.self(), action: :initialized}
    {:noreply, %{state | updates: Updates.add(updates, value, rounds)}}
  end

  def handle_info({:push, from, updates}, state) do
    {:noreply, do_push_request(updates, from, state)}
  end

  def handle_info({:feedback, known_updates}, state) do
    {:noreply, %{state | updates: do_feedback(known_updates, state)}}
  end

  defp do_gossip(%{
         name: name,
         membership_module: msm,
         updates: updates,
         level: level
       }) do
    random(msm.list(), level)
    |> push(ref(name, msm.self()), name, Updates.infected(updates) |> Updates.values())
  end

  defp do_feedback(known_updates, %{updates: updates}), do: Updates.count(updates, known_updates)

  defp do_push_request(
         new_updates,
         from,
         %{
           handler: handler,
           updates: updates,
           rounds: rounds
         } = state
       ) do
    case apply(handler, :push, [new_updates, updates]) do
      :ok ->
        %{state | updates: give_feedback(updates, new_updates, from, rounds)}

      {:ok, new_updates} ->
        %{state | updates: give_feedback(updates, new_updates, from, rounds)}

      :ignore ->
        state
    end
  end

  defp give_feedback(updates, new_updates, from, rounds) do
    new_updates = Updates.new(new_updates, rounds)
    send(from, {:feedback, Updates.known(updates, new_updates)})
    Updates.merge(updates, new_updates)
  end

  defp push([], _, _, _), do: :ignore
  defp push(_, _, _, []), do: :ignore

  defp push(nodes, from, name, updates) do
    Enum.each(nodes, &send(ref(name, &1), {:push, from, updates}))
  end

  defp ref(ref, _node) when is_pid(ref), do: ref
  defp ref(ref, node) when is_atom(ref), do: {ref, node}

  defp random(nodes, n), do: Enum.shuffle(nodes) |> Enum.take(n)

  defp delta(pid, timeout \\ 0), do: Process.send_after(pid, :delta, timeout)
  defp gc(pid, timeout \\ 0), do: Process.send_after(pid, :gc, timeout)
  defp initialized(pid, timeout \\ 0), do: Process.send_after(pid, :initialized, timeout)
end
