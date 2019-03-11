defmodule Grapevine.Support.Bench do
  def get_pid(node), do: :rpc.block_call(node, Process, :whereis, [:gsp1])

  def in_sync?(n, size) do
    %{updates: slave0_updates} = :slave_0@localhost |> get_pid() |> :sys.get_state()
    slave0_messages = filter(slave0_updates)

    Enum.all?(1..(n - 1), fn i ->
      %{updates: updates} = :"slave_#{i}@localhost" |> get_pid() |> :sys.get_state()
      slave_messages = filter(updates)
      equal_keys?(slave_messages, slave0_messages) && Enum.count(slave_messages) == size
    end)
  end

  def assert(result, message) do
    case result do
      true -> :ok
      _ -> throw("assert failed: #{message}")
    end
  end

  defp equal_keys?(map1, map2) do
    Map.keys(map1) == Map.keys(map2)
  end

  defp filter(map) do
    Enum.filter(map, fn
      {_k, %{value: %{action: _}}} -> false
      _m -> true
    end)
    |> Map.new()
  end
end
