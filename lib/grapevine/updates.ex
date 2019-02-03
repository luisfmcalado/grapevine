defmodule Grapevine.Updates do
  @moduledoc """
  List of messages
  """

  @type t :: map()

  alias Grapevine.Message

  @doc """
  Returns a new empty map.

  ## Examples

      iex> Grapevine.Updates.new()
      %{}

  """
  @spec new() :: t()
  def new, do: Map.new()

  @doc """
  Returns a new map from a list of values.

  ## Examples

      iex> Grapevine.Updates.new([1], 2)
      %{
         "55A54008AD1BA589AA210D2629C1DF41" => %Grapevine.Message{
           removed_at: nil, rounds: 2, state: :infected, value: 1
         }
       }

  """
  @spec new([any(), ...], integer()) :: t()
  def new(values, rounds) do
    Enum.reduce(values, new(), fn value, acc ->
      add(acc, value, rounds)
    end)
  end

  @doc """
  Merge two updates into one.

  ## Examples

      iex> Grapevine.Updates.merge(%{
      ...>   "55A54008AD1BA589AA210D2629C1DF41" => %Grapevine.Message{
      ...>     removed_at: nil, rounds: 2, state: :infected, value: 1
      ...>   }
      ...> },
      ...> %{
      ...>   "9E688C58A5487B8EAF69C9E1005AD0BF" => %Grapevine.Message{
      ...>     removed_at: nil, rounds: 2, state: :infected, value: 2
      ...>   }
      ...> })
      %{
        "55A54008AD1BA589AA210D2629C1DF41" => %Grapevine.Message{
          removed_at: nil, rounds: 2, state: :infected, value: 1
         },
        "9E688C58A5487B8EAF69C9E1005AD0BF" => %Grapevine.Message{
          removed_at: nil, rounds: 2, state: :infected, value: 2
        }
      }

  """
  @spec merge(t(), t()) :: t()
  def merge(updates, new_updates) do
    merge_updates(new_updates, updates)
  end

  @doc """
  Add a new value to the updates.

  ## Examples

      iex> Grapevine.Updates.add(%{}, 1, 2)
      %{
        "55A54008AD1BA589AA210D2629C1DF41" => %Grapevine.Message{
          removed_at: nil, rounds: 2, state: :infected, value: 1
        }
      }

  """
  @spec add(t(), any(), integer()) :: t()
  def add(updates, value, rounds) do
    message = Message.new(value, rounds)
    merge_updates(updates, %{Message.hash!(message) => message})
  end

  @doc """
  Update the counter and remove when the counter is zero for every key found

  ## Examples

      iex> Grapevine.Updates.count(%{
      ...>   "55A54008AD1BA589AA210D2629C1DF41" => %Grapevine.Message{
      ...>     removed_at: nil, rounds: 2, state: :infected, value: 1
      ...>   }
      ...> }, ["55A54008AD1BA589AA210D2629C1DF41"])
      %{
        "55A54008AD1BA589AA210D2629C1DF41" => %Grapevine.Message{
          rounds: 1, state: :infected, value: 1
        }
      }
  """
  @spec count(t(), [String.t(), ...]) :: t()
  def count(updates, keys) do
    Enum.reduce(keys, updates, fn k, acc ->
      case Map.get(updates, k) |> Message.count() do
        %{rounds: 0} = message -> merge_updates(acc, %{k => Message.remove(message)})
        message -> merge_updates(acc, %{k => message})
      end
    end)
  end

  @doc """
  Find the messages that are found in both updates.

  ## Examples

      iex> Grapevine.Updates.known(%{
      ...>   "55A54008AD1BA589AA210D2629C1DF41" => %Grapevine.Message{
      ...>     removed_at: nil, rounds: 2, state: :infected, value: 1
      ...>   },
      ...>   "9E688C58A5487B8EAF69C9E1005AD0BF" => %Grapevine.Message{
      ...>     removed_at: nil, rounds: 2, state: :infected, value: 2
      ...>   }
      ...> },
      ...> %{
      ...>   "9E688C58A5487B8EAF69C9E1005AD0BF" => %Grapevine.Message{
      ...>     removed_at: nil, rounds: 2, state: :infected, value: 2
      ...>   }
      ...> })
      ["9E688C58A5487B8EAF69C9E1005AD0BF"]

  """
  @spec known(t(), t()) :: [String.t(), ...] | []
  def known(updates, new_updates) do
    new_keys = Map.keys(new_updates)
    Map.take(updates, new_keys) |> Map.keys()
  end

  @doc """
  Filter the infected messages

  ## Examples

      iex> Grapevine.Updates.infected(%{
      ...>   "55A54008AD1BA589AA210D2629C1DF41" => %Grapevine.Message{
      ...>     removed_at: nil, rounds: 2, state: :removed, value: 1
      ...>   },
      ...>   "9E688C58A5487B8EAF69C9E1005AD0BF" => %Grapevine.Message{
      ...>     removed_at: nil, rounds: 2, state: :infected, value: 2
      ...>   }
      ...> })
      %{
        "9E688C58A5487B8EAF69C9E1005AD0BF" => %Grapevine.Message{
          removed_at: nil, rounds: 2, state: :infected, value: 2
        }
      }

  """
  @spec infected(t()) :: t()
  def infected(updates) do
    updates
    |> Enum.filter(fn {_k, message} ->
      Message.infected?(message)
    end)
    |> Map.new()
  end

  @doc """
  Get values from updates

  ## Examples

      iex> Grapevine.Updates.values(%{
      ...>   "55A54008AD1BA589AA210D2629C1DF41" => %Grapevine.Message{
      ...>     removed_at: nil, rounds: 2, state: :removed, value: 1
      ...>   },
      ...>   "9E688C58A5487B8EAF69C9E1005AD0BF" => %Grapevine.Message{
      ...>     removed_at: nil, rounds: 2, state: :infected, value: 2
      ...>   }
      ...> })
      [1,2]

  """

  @spec values(t()) :: [any(), ...] | []
  def values(updates) do
    Enum.map(updates, fn {_k, %{value: value}} -> value end)
  end

  @doc """
  Clean messages that have expired

  ## Examples

      iex> Grapevine.Updates.clean(%{
      ...>   "55A54008AD1BA589AA210D2629C1DF41" => %Grapevine.Message{
      ...>     removed_at: 0, rounds: 2, state: :removed, value: 1
      ...>   }
      ...> }, 1)
      %{}

  """
  @spec clean(t(), integer()) :: t()
  def clean(updates, threshold) do
    updates
    |> Enum.filter(fn {_k, v} ->
      !Message.expired?(v, threshold)
    end)
    |> Map.new()
  end

  defp merge_updates(updates, new_updates) do
    Map.merge(updates, new_updates)
  end
end
