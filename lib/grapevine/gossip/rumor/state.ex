defmodule Grapevine.Gossip.Rumor.State do
  @moduledoc """
  The rumor mongering message state
  """
  defstruct [:state, :rounds, :removed_at]

  @type t :: %__MODULE__{
          state: atom(),
          rounds: integer(),
          removed_at: nil | integer()
        }

  @doc """
  Returns a new state

  ## Examples

      iex> State.new(2)
      %State{rounds: 2, state: :infected}

  """
  @spec new(integer()) :: t()
  def new(rounds), do: %__MODULE__{rounds: rounds, state: :infected}

  @doc """
  Changes the state to removed

  ## Examples

      iex> State.remove(State.new(0), 0)
      %State{rounds: 0, state: :removed, removed_at: 0}

  """
  @spec remove(t()) :: t()
  def remove(value, removed_at \\ now()),
    do: %__MODULE__{value | state: :removed, removed_at: removed_at}

  @doc """
  Check if the state is infected

  ## Examples

      iex> State.infected?(%State{rounds: 0, state: :removed})
      false
      iex> State.infected?(State.new(1))
      true

  """
  @spec infected?(t()) :: boolean()
  def infected?(%{state: :infected}), do: true
  def infected?(_), do: false

  @doc """
  Checks if the state has expired

  ## Examples

      iex> State.expired?(%State{rounds: 0, state: :removed, removed_at: 0}, 10)
      true
      iex> State.expired?(
      ...>   %State{rounds: 0, state: :removed, removed_at: :os.system_time(:millisecond) - 100}, 200
      ...> )
      false
      iex> State.expired?(%State{rounds: 0, state: :removed, removed_at: nil}, 10)
      false

  """
  @spec expired?(t(), integer()) :: boolean()
  def expired?(%{removed_at: nil}, _), do: false

  def expired?(%{removed_at: removed_at}, threshold) do
    if now() - removed_at > threshold, do: true, else: false
  end

  @doc """
  Decrements the number of state rounds

  ## Examples

      iex> State.dec(State.new(2))
      %State{rounds: 1, state: :infected}
      iex> State.dec(State.new(0))
      %State{rounds: 0, state: :infected}

  """
  @spec dec(t()) :: t()
  def dec(%{rounds: 0} = value), do: value
  def dec(%{rounds: rounds} = value), do: %__MODULE__{value | rounds: rounds - 1}

  defp now(), do: :os.system_time(:millisecond)
end
