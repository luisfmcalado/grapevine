defmodule Grapevine do
  @moduledoc """
  The API for grapevine
  """

  @doc """
  Starts grapevine.
  """
  @spec start_link(atom(), keyword()) :: term()
  def start_link(handler, opts) do
    opts
    |> Keyword.put(:handler, handler)
    |> Grapevine.Supervisor.start_link()
  end

  @doc """
  Adds a new update to the gossip instance. The update will be propagated
  to all processes within the cluster that have the same name.
  """
  @spec add(atom(), any(), timeout()) :: term()
  def add(name, value, timeout \\ 5000) do
    GenServer.call(name, {:add, value}, timeout)
  end
end
