defmodule Grapevine.Support.Generator do
  use Agent

  def start_link(), do: Agent.start_link(fn -> 0 end, name: __MODULE__)
  def reset, do: Agent.get_and_update(__MODULE__, &{&1, 0})
  def next, do: Agent.get_and_update(__MODULE__, &{&1, &1 + 1})
end
