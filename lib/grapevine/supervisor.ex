defmodule Grapevine.Supervisor do
  @moduledoc false
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts)
  end

  def init(opts) do
    handler = Keyword.fetch!(opts, :handler)
    membership_module = Keyword.fetch!(opts, :membership_module)
    membership_opts = Keyword.fetch!(opts, :membership_opts)

    children = [
      {Grapevine.Gossip, [handler, opts]},
      {membership_module, membership_opts}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
