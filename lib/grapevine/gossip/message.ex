defmodule Grapevine.Gossip.Message do
  @moduledoc false

  @doc """
  Returns the hash value for the message

  ## Examples

      iex> Message.hash!(%{field: :value})
      "A3957CC79D6F84B4E6254DE44D201513"

  """
  @spec hash!(map()) :: String.t()
  def hash!(value), do: :crypto.hash(:md5, pack!(value)) |> Base.encode16()

  defp pack!(value), do: Msgpax.pack!(value)
end
