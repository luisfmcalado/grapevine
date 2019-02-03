defmodule Grapevine.Support.Wait do
  def wait(_n, _s, 0), do: false

  def wait(f, s, r) do
    if f.() do
      Process.sleep(s)
      wait(f, s, r - 1)
    else
      true
    end
  end
end
