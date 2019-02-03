initial_state = %{
  self: self(),
  name: :gsp1,
  handler: Grapevine.Support.DummyHandler,
  delta: 1000,
  updates: Grapevine.Updates.new(),
  membership_module: Grapevine.Node,
  rounds: 1,
  level: 2
}

setup_values = fn size ->
  values =
    Enum.reduce(0..size, [], fn n, acc ->
      acc ++ [%{value: n}]
    end)

  updates = Grapevine.Updates.new(values, 1)
  state = Map.put(initial_state, :updates, updates)
  keys = Map.keys(updates)

  {values, updates, keys, state}
end

Benchee.run(
  %{
    "delta" => fn {_, _, _, state} -> Grapevine.Gossip.handle_info(:delta, state) end,
    "push" => fn {values, _, _, _} ->
      Grapevine.Gossip.handle_info({:push, self(), values}, initial_state)
    end,
    "feedback" => fn {_, _, keys, state} ->
      Grapevine.Gossip.handle_info({:feedback, keys}, state)
    end
  },
  inputs: %{
    "100 updates" => setup_values.(10),
    "1000 updates" => setup_values.(1000),
    "10_000 updates" => setup_values.(10_000)
  }
)
