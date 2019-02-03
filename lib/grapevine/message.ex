defmodule Grapevine.Message do
  @moduledoc """
  The value envelope for grapevine
  """
  defstruct [:value, :state, :rounds, :removed_at]

  @type t :: %__MODULE__{
          value: any(),
          state: atom(),
          rounds: integer(),
          removed_at: nil | integer()
        }

  @doc """
  Returns a new message

  ## Examples

      iex> Grapevine.Message.new(1, 2)
      %Grapevine.Message{value: 1, rounds: 2, state: :infected}

  """
  @spec new(any(), integer()) :: t()
  def new(value, rounds) do
    %__MODULE__{value: value, rounds: rounds, state: :infected}
  end

  @doc """
  Returns the hash value for the message

  ## Examples

      iex> Grapevine.Message.hash!(%Grapevine.Message{value: 1, rounds: 2, state: :infected})
      "55A54008AD1BA589AA210D2629C1DF41"

  """
  @spec hash!(t()) :: String.t()
  def hash!(%{value: value}), do: :crypto.hash(:md5, pack!(value)) |> Base.encode16()

  @doc """
  Changes the message state and updates the remove timestamp

  ## Examples

      iex> Grapevine.Message.remove(%Grapevine.Message{value: 1, rounds: 0, state: :infected}, 0)
      %Grapevine.Message{value: 1, rounds: 0, state: :removed, removed_at: 0}

  """
  @spec remove(t()) :: t()
  def remove(value, removed_at \\ now()),
    do: %__MODULE__{value | state: :removed, removed_at: removed_at}

  @doc """
  Check if the message state is infected

  ## Examples

      iex> Grapevine.Message.infected?(%Grapevine.Message{value: 1, rounds: 0, state: :removed})
      false
      iex> Grapevine.Message.infected?(%Grapevine.Message{value: 1, rounds: 1, state: :infected})
      true

  """
  @spec infected?(t()) :: boolean()
  def infected?(%{state: :infected}), do: true
  def infected?(_), do: false

  @doc """
  Checks if the message has expired

  ## Examples

      iex> Grapevine.Message.expired?(%Grapevine.Message{value: 1, rounds: 0, state: :removed, removed_at: 0}, 10)
      true
      iex> Grapevine.Message.expired?(
      ...>   %Grapevine.Message{value: 1, rounds: 0, state: :removed, removed_at: :os.system_time(:millisecond) - 100}, 200
      ...> )
      false
      iex> Grapevine.Message.expired?(%Grapevine.Message{value: 1, rounds: 0, state: :removed, removed_at: nil}, 10)
      false

  """
  @spec expired?(t(), integer()) :: boolean()
  def expired?(%{removed_at: nil}, _), do: false

  def expired?(%{removed_at: removed_at}, threshold) do
    if now() - removed_at > threshold, do: true, else: false
  end

  @doc """
  Decrements the number of rounds

  ## Examples

      iex> Grapevine.Message.count(%Grapevine.Message{value: 1, rounds: 2, state: :infected})
      %Grapevine.Message{value: 1, rounds: 1, state: :infected}

  """
  @spec count(t()) :: t()
  def count(%{rounds: rounds} = value), do: %__MODULE__{value | rounds: rounds - 1}

  defp pack!(value), do: Msgpax.pack!(value)
  defp now(), do: :os.system_time(:millisecond)
end
