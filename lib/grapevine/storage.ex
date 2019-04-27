defmodule Grapevine.Storage do
  @moduledoc """
  This module is the interface for custom storage modules.
  """

  defmacro __using__(_) do
    quote do
      @behaviour Grapevine.Storage
    end
  end

  @type t :: {sequence :: non_neg_integer(), crdt :: any()}

  @doc """
  Initialize storage device
  """
  @callback init(args :: keyword()) :: {:ok, any()} | {:error, any()}

  @doc """
  Write to storage device
  """
  @callback write(id :: atom(), value :: t()) :: :ok | {:error, any()}

  @doc """
  Read from device
  """
  @callback read(id :: atom()) :: {:ok, t()} | {:error, any()}
end
