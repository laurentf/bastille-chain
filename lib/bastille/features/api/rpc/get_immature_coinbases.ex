defmodule Bastille.Features.Api.RPC.GetImmatureCoinbases do
  @moduledoc """
  Handles the get_immature_coinbases RPC command.
  Returns all immature coinbase rewards for a given address.
  """
  
  alias Bastille.Features.Tokenomics.CoinbaseMaturity
  alias Bastille.Features.Tokenomics.Token

  def call(%{"address" => address}) do
    immature_coinbases = CoinbaseMaturity.get_immature_coinbases(address)
    
    formatted_coinbases = Enum.map(immature_coinbases, fn reward ->
      %{
        block_hash: Base.encode16(reward.block_hash, case: :lower),
        amount: reward.amount,
        amount_bast: Token.format_bast(reward.amount),
        block_height: reward.block_height,
        maturity_height: reward.maturity_height,
        created_at: reward.created_at,
        status: reward.status,
        blocks_remaining: max(0, reward.maturity_height - get_current_height())
      }
    end)
    
    %{
      address: address,
      immature_coinbases: formatted_coinbases,
      total_immature_amount: Enum.reduce(formatted_coinbases, 0, &(&1.amount + &2)),
      count: length(formatted_coinbases)
    }
  rescue
    error -> %{error: Exception.message(error)}
  end

  def call(_), do: %{error: "Missing or invalid 'address' parameter"}

  defp get_current_height do
    case Bastille.Features.Chain.Chain.get_height() do
      height when is_integer(height) -> height
      _ -> 0
    end
  end
end