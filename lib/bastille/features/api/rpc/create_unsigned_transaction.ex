defmodule Bastille.Features.Api.RPC.CreateUnsignedTransaction do
  @moduledoc """
  Creates an unsigned transaction for later signing by external wallets (MetaMask-style).

  This enables the standard Web3 workflow:
  1. DApp creates unsigned transaction
  2. Wallet (MetaMask, etc.) signs transaction
  3. DApp submits signed transaction
  """

  alias Bastille.Features.Chain.Chain
  alias Bastille.Features.Tokenomics.Token
  alias Bastille.Features.Transaction.Transaction

  def call(params) do
    from = params["from"] || params["from_address"]
    to = params["to"] || params["to_address"]
    amount = params["amount"]
    data = params["data"] || <<>>
    fee = params["fee"] # Optional, will be auto-calculated if nil

    case create_unsigned_transaction(from, to, amount, data, fee) do
      {:ok, unsigned_tx} ->
        %{
          "result" => %{
            "unsigned_transaction" => Base.encode64(:erlang.term_to_binary(unsigned_tx)),
            "transaction_hash" => Base.encode16(unsigned_tx.hash, case: :lower)
          }
        }
      {:error, reason} ->
        %{"error" => %{"code" => -32_602, "message" => "Transaction creation failed: #{inspect(reason)}"}}
    end
  rescue
    error -> %{"error" => %{"code" => -32_602, "message" => "Failed to create transaction: #{Exception.message(error)}"}}
  end

  # Pattern matching for fee calculation
  defp calculate_fee_juillet(nil, data), do: Token.calculate_fee(byte_size(data), :normal)
  defp calculate_fee_juillet(fee, _data) when is_float(fee), do: Token.bast_to_juillet(fee)
  defp calculate_fee_juillet(fee, _data), do: fee

  defp create_unsigned_transaction(from, to, amount, data, fee) do
    # Use Bastille facade to create unsigned transaction
    # Convert amount to juillet if needed
    amount_juillet = if is_float(amount) do
      Token.bast_to_juillet(amount)
    else
      amount
    end

    # Calculate fee if not provided
    fee_juillet = calculate_fee_juillet(fee, data)

    # Validate addresses
    with :ok <- Bastille.validate_address(from),
         :ok <- Bastille.validate_address(to) do

      # Get current nonce
      current_nonce = Chain.get_nonce(from)

      # Create unsigned transaction
      unsigned_tx = Transaction.new([
        from: from,
        to: to,
        amount: amount_juillet,
        fee: fee_juillet,
        nonce: current_nonce + 1,
        data: data,
        signature_type: :post_quantum_2_of_3
      ])

      {:ok, unsigned_tx}
    else
      error -> error
    end
  end
end
