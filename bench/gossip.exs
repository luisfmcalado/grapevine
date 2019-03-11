initial_state = %{
  self: self(),
  name: :gsp1,
  handler: Grapevine.Support.DummyHandler,
  delta: 1000,
  updates: %{},
  meta: %{},
  membership_module: Grapevine.Node,
  rounds: 1,
  level: 2
}

setup_values = fn size ->
  values =
    Enum.reduce(0..size, [], fn n, acc ->
      acc ++ [{n, n}]
    end)

  updates = %{"1" => %{value: 1}}
  meta = %{"1" => Grapevine.Gossip.Rumor.State.new(2)}
  state = Map.put(initial_state, :updates, updates)
  state = Map.put(state, :meta, meta)
  keys = Map.keys(updates)

  {values, updates, keys, state}
end

Benchee.run(
  %{
    "delta" => fn {_, _, _, state} -> Grapevine.Gossip.Rumor.handle_info(:delta, state) end,
    "push" => fn {values, _, _, _} ->
      Grapevine.Gossip.Rumor.handle_info({:push, self(), values}, initial_state)
    end,
    "feedback" => fn {_, _, keys, state} ->
      Grapevine.Gossip.Rumor.handle_info({:feedback, keys}, state)
    end
  },
  inputs: %{
    "100 updates" => setup_values.(10),
    "1000 updates" => setup_values.(1000),
    "10_000 updates" => setup_values.(10_000)
  }
)

Benchee.run(
  %{
    "delta" => fn {_, _, _, state} -> Grapevine.Gossip.Entropy.handle_info(:delta, state) end,
    "push" => fn {values, _, _, _} ->
      Grapevine.Gossip.Entropy.handle_info({:push, self(), values}, initial_state)
    end
  },
  inputs: %{
    "100 updates" => setup_values.(10),
    "1000 updates" => setup_values.(1000),
    "10_000 updates" => setup_values.(10_000)
  }
)
