defmodule Grapevine do
  @moduledoc """
  The API for grapevine
  """

  @doc """
  Starts grapevine.
  """
  @spec start_link(module(), module(), keyword()) :: term()
  def start_link(gossip, handler, opts) do
    opts
    |> Keyword.put(:gossip, gossip)
    |> Keyword.put(:handler, handler)
    |> Grapevine.Supervisor.start_link()
  end

  @doc """
  Adds a new update to the gossip instance. The update will be propagated
  to all processes within the cluster that have the same name.
  """
  @spec add(atom(), any(), binary(), timeout()) :: term()
  def add(name, value, id, timeout \\ 5000) do
    Grapevine.Gossip.add(name, value, id, timeout)
  end
end
