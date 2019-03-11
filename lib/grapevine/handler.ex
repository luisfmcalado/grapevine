defmodule Grapevine.Handler do
  @moduledoc """
  This module is the interface for custom handlers.

  The handler can be used to process new updates and detect new nodes added to the network.
  """
  alias Grapevine.Updates

  defmacro __using__(_) do
    quote do
      @behaviour Grapevine.Handler
    end
  end

  @doc """
  The push callback receives all the updates sent. The callback can be used to process
  the updates, filter the updates and ignore. The ignored or filtered updates won't be
  process by the instance, i.e. the feedback step won't include these updates
  """
  @callback push(Updates.t(), Updates.t()) ::
              :ok | {:ok, Updates.t()} | {:reset, Updates.t()} | :ignore
end
