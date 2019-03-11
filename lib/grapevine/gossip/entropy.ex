defmodule Grapevine.Gossip.Entropy do
  @moduledoc false

  use Grapevine.Gossip

  def do_init(state, _opts), do: {:ok, state}

  def filter(%{updates: updates}), do: updates

  def push(
        new_updates,
        _from,
        %{
          handler: handler,
          updates: updates
        }
      ) do
    new_updates =
      Enum.reduce(new_updates, Map.new(), fn {k, v}, acc ->
        Map.put(acc, k, %{value: v})
      end)

    case apply(handler, :push, [new_updates, updates]) do
      :ok -> %{updates: Map.merge(updates, new_updates)}
      {:ok, new_updates} -> %{updates: Map.merge(updates, new_updates)}
      {:reset, new_updates} -> %{updates: new_updates}
      :ignore -> %{updates: updates}
    end
  end

  def neighbours(%{membership_module: msm}), do: msm.list()

  def merge(id, value, %{updates: updates}),
    do: %{updates: Map.merge(updates, %{id => %{value: value}})}
end
