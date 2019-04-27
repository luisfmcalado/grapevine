defmodule Grapevine.Support.DeltaCRDT.GCounter do
  @enforce_keys [:id]

  defstruct payload: Map.new(), id: nil
  @opaque t :: %__MODULE__{}

  def new(id), do: %__MODULE__{id: id}
  def inc(%__MODULE__{id: id, payload: payload} = g_counter, n \\ 1) do
    update = %{id => get(g_counter) + n}

    {
      %__MODULE__{g_counter | payload: Map.merge(payload, update)},
      %__MODULE__{g_counter | payload: update}
    }
  end

  def value(%__MODULE__{payload: payload}) do
    Enum.reduce(payload, 0, fn {_k, v}, acc -> acc + v end)
  end

  def compare(%__MODULE__{payload: payload}, crdt) do
    Enum.all?(payload, fn {k, v} -> v <= get_by_key(crdt, k) end)
  end

  def merge(g_counter_1, g_counter_2) do
    payload =
      Map.merge(g_counter_1.payload, g_counter_2.payload, fn _k, v1, v2 ->
        max(v1, v2)
      end)

    %__MODULE__{g_counter_1 | payload: payload}
  end

  defp get(%__MODULE__{id: id, payload: payload}), do: Map.get(payload, id, 0)
  defp get_by_key(%__MODULE__{payload: payload}, key), do: Map.get(payload, key, 0)
end
