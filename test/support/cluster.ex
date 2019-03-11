defmodule Grapevine.Support.Cluster do
  alias Grapevine.Support.DummyHandler

  def setup_distributed() do
    Node.start(:master@localhost, :shortnames)
    :erl_boot_server.start([])
  end

  def init_slaves(n, gossip, handler \\ DummyHandler, opts \\ []) do
    Enum.each(0..(n - 1), fn index ->
      start_slave(index, gossip, handler, opts)
    end)
  end

  def start_slave(index, gossip, handler \\ DummyHandler, opts \\ []) do
    {:ok, node} = :slave.start_link(:localhost, 'slave_#{index}')
    rpc(node, :code, :add_paths, [:code.get_path()])

    for {app_name, _, _} <- Application.loaded_applications() do
      for {key, val} <- Application.get_all_env(app_name) do
        rpc(node, Application, :put_env, [app_name, key, val])
      end
    end

    name = Keyword.get(opts, :name, :gsp1)

    opts =
      Keyword.merge(
        [
          name: name,
          membership_module: Grapevine.Node,
          membership_opts: [
            mfa: {Grapevine, :add, [name]}
          ]
        ],
        opts
      )

    rpc(node, Application, :ensure_all_started, [:mix])
    rpc(node, Mix, :env, [Mix.env()])
    {:ok, _} = rpc(node, Grapevine, :start_link, [gossip, handler, opts])

    for {app_name, _, _} <- Application.loaded_applications() do
      rpc(node, Application, :ensure_all_started, [app_name])
    end
  end

  def slaves_connected?(n) do
    nodes_list = Node.list()

    Enum.all?(0..(n - 1), fn index ->
      slave_name(index) in nodes_list
    end)
  end

  def stop_master() do
    Node.stop()
  end

  def stop_slaves(n) do
    Enum.each(0..(n - 1), fn index ->
      stop_slave(index)
    end)
  end

  def stop_slave(index) do
    slave_name(index)
    |> :slave.stop()
  end

  defp slave_name(index) do
    :"slave_#{index}@localhost"
  end

  defp rpc(node, module, fun, args) do
    :rpc.block_call(node, module, fun, args)
  end
end
