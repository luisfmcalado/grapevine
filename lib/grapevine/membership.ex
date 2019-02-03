defmodule Grapevine.Membership do
  @moduledoc """
  This module is the interface for custom membership modules.
  """

  defmacro __using__(_) do
    quote do
      @behaviour Grapevine.Membership

      use GenServer
    end
  end

  @doc """
  List of nodes connected to the current node.
  """
  @callback list() :: [atom(), ...]

  @doc """
  Returns the name of the current node.
  """
  @callback self() :: atom()
end
