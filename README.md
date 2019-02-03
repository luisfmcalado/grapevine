# Grapevine

[![Hex pm](http://img.shields.io/hexpm/v/grapevine.svg?style=flat)](https://hex.pm/packages/grapevine) [![CircleCI](https://circleci.com/gh/luisfmcalado/grapevine.svg?style=svg)](https://circleci.com/gh/luisfmcalado/grapevine) [![codecov](https://codecov.io/gh/luisfmcalado/grapevine/branch/master/graph/badge.svg?token=Gp58S4Tut2)](https://codecov.io/gh/luisfmcalado/grapevine)

Rumor mongering protocol for Elixir

The grapevine is based on the SIR model (complex epidemics/rumor mongering) and the variant feedback/counter. Each update can have one of three states: susceptible, infected and removed. If a new update is added it will be handled by each instance and you can process and/or ignore the update. The handle can be used to check if a node is added to the network and you might want to sync the new node. The updates are stored in memory until they become removed and the time to live hasn't expired. If the garbage collector is triggered then the updates will be removed.

The options can have an impact on the consistency because the rumor mongering protocols cannot guarantee the delivery to every instance. With the right configuration, the probability of such an event is very low but is never zero.

## Installation

```elixir
defp deps do
  [{:grapevine, "~> 0.1"}]
end
```

## Configuration

#### Required `opts`:
  - `module` - The handler module that implements the behaviour `Grapevine.Handler`.
  - `membership_module` - The module responsible for the membership. The `Grapevine.Node` is 
  the module to use if you want to track the `nodeup` and `nodedown` info messages. This can be done with the `Grapevine.Handler` that will receive 
  these changes.
  - `membership_opts` - The membership module options.

#### Optional `opts`:
  - `name` - The name of the gossip process. The default name is `Grapevine.Gossip`.
  - `rounds` - The number of rounds for the feedback. Default `3`.
  - `level` - The number of nodes randomly selected for each cycle. Default `1`.
  - `gc` - The interval in milliseconds for the garbage collector. Default `1000`.
  - `ttl` - The time to live in milliseconds for removed messages. Default `30000`. 
  - `delta` - The timeout for each gossip cycle. Default `500`.

## Example

In the example folder you can find a dummy handler used with grapevine.

```elixir
defmodule SomeHandler do
  use Grapevine.Handler
   
  def push(received_values, stored_values) do
    # do something with these values, filter or ignore
    :ok
  end
end
```

```elixir
opts = [
  name: :gossip
  membership_module: Grapevine.Node,
  membership_opts: [
    mfa: {Grapevine, :add, [:gossip]}
  ]
]

Grapevine.start(Grapevine.DummyHandler, opts)
Grapevine.add(:gossip, %{value: 101, id: "1"})
```

## License

MIT
