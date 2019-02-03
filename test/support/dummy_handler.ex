defmodule Grapevine.Support.DummyHandler do
  use Grapevine.Handler

  def push(_n, _u) do
    :ok
  end
end
