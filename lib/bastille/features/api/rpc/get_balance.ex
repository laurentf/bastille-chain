defmodule Bastille.Features.Api.RPC.GetBalance do
  @moduledoc """
  Handles the get_balance RPC command.

  Validates the address format (including EIP-55-inspired checksum if
  mixed-case is supplied) before looking up the balance — so that a
  mistyped address returns a clear error rather than `balance: 0` (which
  would silently misinform a wallet client).
  """

  alias Bastille.Features.Chain.Chain
  alias Bastille.Shared.Address

  def call(%{"address" => address}) when is_binary(address) do
    case Address.valid?(address) do
      true ->
        canonical = Address.canonical(address)

        %{
          address: canonical,
          balance: Chain.get_balance(canonical),
          nonce: Chain.get_nonce(canonical)
        }

      false ->
        %{error: "Invalid address format or checksum mismatch"}
    end
  rescue
    error -> %{error: Exception.message(error)}
  end

  def call(_), do: %{error: "Missing or invalid 'address' parameter"}
end
