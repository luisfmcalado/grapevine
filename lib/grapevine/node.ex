defmodule Grapevine.Node do
  @moduledoc false
  use Grapevine.Membership

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(opts) do
    :ok = :net_kernel.monitor_nodes(true)

    state = %{
      mfa: Keyword.fetch!(opts, :mfa)
    }

    {:ok, state}
  end

  def handle_info({:nodeup, node}, state) do
    do_node_action(:nodeup, node, state)
    {:noreply, state}
  end

  def handle_info({:nodedown, node}, state) do
    do_node_action(:nodedown, node, state)
    {:noreply, state}
  end

  defp do_node_action(action, node, %{mfa: {m, f, a}}) do
    apply(m, f, a ++ [%{node: node, action: action}])
  end

  defdelegate list(), to: Node
  defdelegate self(), to: Node
end
