defmodule Bastille.Features.Transaction.TransactionConverter do
  @moduledoc """
  Safe conversion of P2P transaction data (maps) into Transaction structs.

  Symmetric with `Bastille.Features.Block.BlockConverter`: every field is
  validated before the struct is rebuilt, so a malformed or hostile P2P payload
  can never yield a partial transaction. Semantic validation (signature, fees,
  nonce) is left to the mempool.
  """

  alias Bastille.Features.Transaction.Transaction
  alias Bastille.Shared.Address
  require Logger

  @doc """
  Convert P2P data into a Transaction struct, validating every field.
  """
  @spec from_p2p_data(map()) :: {:ok, Transaction.t()} | {:error, term()}
  def from_p2p_data(tx_data) when is_map(tx_data) do
    with {:ok, from} <- extract_address(tx_data, ["from", :from]),
         {:ok, to} <- extract_address(tx_data, ["to", :to]),
         {:ok, amount} <- extract_non_neg_integer(tx_data, ["amount", :amount]),
         {:ok, fee} <- extract_non_neg_integer(tx_data, ["fee", :fee]),
         {:ok, nonce} <- extract_non_neg_integer(tx_data, ["nonce", :nonce]),
         {:ok, timestamp} <- extract_non_neg_integer(tx_data, ["timestamp", :timestamp]),
         {:ok, hash} <- extract_hash(tx_data, ["hash", :hash]),
         {:ok, signature_type} <- extract_signature_type(tx_data),
         {:ok, signature} <- extract_signature(tx_data),
         {:ok, public_keys} <- extract_public_keys(tx_data),
         {:ok, data} <- extract_data(tx_data) do
      tx = %Transaction{
        from: from,
        to: to,
        amount: amount,
        fee: fee,
        nonce: nonce,
        timestamp: timestamp,
        hash: hash,
        signature_type: signature_type,
        signature: signature,
        public_keys: public_keys,
        data: data
      }

      {:ok, tx}
    else
      {:error, reason} = error ->
        Logger.warning("❌ Transaction conversion failed: #{inspect(reason)}")
        error
    end
  end

  def from_p2p_data(_), do: {:error, :invalid_transaction_data}

  defp extract_address(data, keys) do
    case find_value(data, keys) do
      value when is_binary(value) ->
        if Address.valid?(value), do: {:ok, value}, else: {:error, {:invalid_address, value}}

      _ ->
        {:error, :missing_address}
    end
  end

  defp extract_non_neg_integer(data, keys) do
    case find_value(data, keys) do
      value when is_integer(value) and value >= 0 -> {:ok, value}
      _ -> {:error, {:invalid_integer, hd(keys)}}
    end
  end

  defp extract_hash(data, keys) do
    case find_value(data, keys) do
      hash when is_binary(hash) and byte_size(hash) == 32 -> {:ok, hash}
      _ -> {:error, :invalid_hash}
    end
  end

  defp extract_signature_type(data) do
    case find_value(data, ["signature_type", :signature_type]) do
      # The real signer (RPC sign_transaction) emits post_quantum_2_of_3; it must
      # be accepted here or signed user txs can't propagate between nodes.
      t when t in ["post_quantum_2_of_3", :post_quantum_2_of_3] -> {:ok, :post_quantum_2_of_3}
      t when t in ["regular", :regular] -> {:ok, :regular}
      t when t in ["coinbase", :coinbase] -> {:ok, :coinbase}
      other -> {:error, {:invalid_signature_type, other}}
    end
  end

  defp extract_signature(data) do
    case find_value(data, ["signature", :signature]) do
      signature when is_map(signature) -> {:ok, signature}
      _ -> {:error, :invalid_signature}
    end
  end

  # Optional. Authenticity is enforced by Transaction.verify_signature (keys
  # must hash to `from`), so we only validate shape here.
  defp extract_public_keys(data) do
    case find_value(data, ["public_keys", :public_keys]) do
      nil ->
        {:ok, nil}

      %{dilithium: d, falcon: f, sphincs: s}
      when is_binary(d) and is_binary(f) and is_binary(s) ->
        {:ok, %{dilithium: d, falcon: f, sphincs: s}}

      _ ->
        {:error, :invalid_public_keys}
    end
  end

  defp extract_data(data) do
    case find_value(data, ["data", :data]) do
      value when is_binary(value) -> {:ok, value}
      nil -> {:ok, ""}
      _ -> {:error, :invalid_data}
    end
  end

  defp find_value(data, [key | rest]) do
    case Map.get(data, key) do
      nil -> find_value(data, rest)
      value -> value
    end
  end

  defp find_value(_data, []), do: nil
end
