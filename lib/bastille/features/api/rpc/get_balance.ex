defmodule Bastille.Features.Api.RPC.GetBalance do
  @moduledoc """
  Handles the get_balance RPC command.
  Returns the balance breakdown for a given address including total, mature, and immature balances.
  """
  
  alias Bastille.Features.Tokenomics.CoinbaseMaturity

  def call(%{"address" => address}) do
    balance_breakdown = CoinbaseMaturity.get_balance_breakdown(address)
    
    %{
      address: address,
      total_balance: balance_breakdown.total,
      mature_balance: balance_breakdown.mature,
      immature_balance: balance_breakdown.immature,
      # For backward compatibility
      balance: balance_breakdown.total
    }
  rescue
    error -> %{error: Exception.message(error)}
  end

  def call(_), do: %{error: "Missing or invalid 'address' parameter"}

end
