defmodule Grapevine.DummyHandler do
  use Grapevine.Handler

  require Logger

  def push(n, u) do
    Logger.info("new updates: #{inspect n}")
    Logger.info("known updates: #{inspect u}")
    :ok
  end
end
