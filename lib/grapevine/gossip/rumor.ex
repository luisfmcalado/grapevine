defmodule Grapevine.Gossip.Rumor do
  @moduledoc false

  use Grapevine.Gossip

  alias Grapevine.Gossip.Rumor.State
  alias Grapevine.Gossip.Message

  def handle_info(
        :gc,
        %{self: pid, updates: updates, meta: meta, gc: timeout, ttl: ttl} = state
      ) do
    gc(pid, timeout)
    {:noreply, Map.merge(state, clean(updates, meta, ttl))}
  end

  def handle_info(:initialized, %{membership_module: msm} = state) do
    value = %{node: msm.self(), action: :initialized}
    {:noreply, Map.merge(state, add_new_update(Message.hash!(value), value, state))}
  end

  def handle_info({:feedback, known_updates}, state) do
    {:noreply, %{state | meta: do_feedback(known_updates, state)}}
  end

  def do_init(%{self: self} = state, opts) do
    if Keyword.get(opts, :gc, true), do: gc(self)
    initialized(self)

    state =
      Map.merge(
        state,
        %{
          level: Keyword.get(opts, :level, 1),
          rounds: Keyword.get(opts, :rounds, 3),
          gc: Keyword.get(opts, :gc, 1000),
          ttl: Keyword.get(opts, :ttl, 30000),
          meta: Map.new()
        }
      )

    {:ok, state}
  end

  def filter(%{updates: updates, meta: meta}) do
    Enum.filter(updates, fn {k, _v} ->
      Map.get(meta, k) |> State.infected?()
    end)
  end

  def push(
        new_updates,
        from,
        %{
          handler: handler,
          updates: updates,
          meta: meta,
          rounds: rounds
        }
      ) do
    new_updates =
      Enum.reduce(new_updates, Map.new(), fn {k, v}, acc ->
        Map.put(acc, k, %{value: v})
      end)

    case apply(handler, :push, [new_updates, updates]) do
      :ok ->
        send_feedback(updates, new_updates, from)
        %{updates: Map.merge(updates, new_updates), meta: add_new_meta(new_updates, meta, rounds)}

      {:ok, new_updates} ->
        send_feedback(updates, new_updates, from)
        %{updates: Map.merge(updates, new_updates), meta: add_new_meta(new_updates, meta, rounds)}

      {:reset, new_updates} ->
        send_feedback(updates, new_updates, from)
        %{updates: new_updates, meta: add_new_meta(new_updates, meta, rounds)}

      :ignore ->
        %{updates: updates}
    end
  end

  def neighbours(%{membership_module: msm, level: level}), do: msm.list() |> random(level)

  def merge(id, value, state), do: add_new_update(id, value, state)

  defp add_new_meta(updates, meta, rounds),
    do:
      Enum.reduce(updates, meta, fn {k, _v}, acc -> Map.merge(%{k => State.new(rounds)}, acc) end)

  defp add_new_update(id, value, %{updates: updates, meta: meta, rounds: rounds}) do
    %{
      updates: Map.put(updates, id, %{value: value}),
      meta: Map.put(meta, id, State.new(rounds))
    }
  end

  defp send_feedback(updates, new_updates, from),
    do: send(from, {:feedback, known(updates, new_updates)})

  defp do_feedback(known_updates, %{meta: meta}), do: dec(meta, known_updates)

  defp random(nodes, n) when n < 1, do: nodes
  defp random(nodes, n), do: Enum.shuffle(nodes) |> Enum.take(n)

  defp gc(pid, timeout \\ 0), do: Process.send_after(pid, :gc, timeout)
  defp initialized(pid, timeout \\ 0), do: Process.send_after(pid, :initialized, timeout)

  defp clean(updates, meta, threshold) do
    meta
    |> Enum.reduce(%{updates: updates, meta: meta}, fn {k, v}, acc ->
      case State.expired?(v, threshold) do
        false ->
          acc

        true ->
          %{updates: updates, meta: meta} = acc
          %{updates: Map.drop(updates, [k]), meta: Map.drop(meta, [k])}
      end
    end)
    |> Map.new()
  end

  defp known(updates, new_updates) do
    new_keys = Map.keys(new_updates)
    Map.take(updates, new_keys) |> Map.keys()
  end

  defp dec(updates, keys) do
    Enum.reduce(keys, updates, fn k, acc ->
      case Map.get(updates, k) |> State.dec() do
        %{rounds: 0} = message -> Map.merge(acc, %{k => State.remove(message)})
        message -> Map.merge(acc, %{k => message})
      end
    end)
  end
end
