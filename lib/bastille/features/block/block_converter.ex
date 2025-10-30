defmodule Bastille.Features.Block.BlockConverter do
  @moduledoc """
  Safe conversion of P2P data into Block structs.

  Converts blocks received via P2P (maps) into Elixir structs with full validation.
  """

  alias Bastille.Features.Block.Block
  require Logger

  @doc """
  Convert P2P data into a Block struct.

  Validates structure and converts transactions.
  """
  @spec from_p2p_data(map()) :: {:ok, Block.t()} | {:error, term()}
  def from_p2p_data(block_data) when is_map(block_data) do
    with {:ok, hash} <- extract_hash(block_data),
         {:ok, header} <- extract_header(block_data),
         {:ok, transactions} <- extract_transactions(block_data) do

      block = %Bastille.Features.Block.Block{
        hash: hash,
        header: header,
        transactions: transactions
      }

      Logger.debug("✅ Block #{header.index} converted from P2P data")
      {:ok, block}
    else
      {:error, reason} = error ->
        Logger.warning("❌ Block conversion failed: #{inspect(reason)}")
        error
    end
  end

  def from_p2p_data(_), do: {:error, :invalid_block_data}

  # Extraction and validation of the hash
  defp extract_hash(%{"hash" => hash}) when is_binary(hash) and byte_size(hash) == 32 do
    {:ok, hash}
  end
  defp extract_hash(%{hash: hash}) when is_binary(hash) and byte_size(hash) == 32 do
    {:ok, hash}
  end
  defp extract_hash(_), do: {:error, :invalid_hash}

  # Extraction and validation of the header
  defp extract_header(%{"header" => header_data}) when is_map(header_data) do
    validate_and_build_header(header_data)
  end
  defp extract_header(%{header: header_data}) when is_map(header_data) do
    validate_and_build_header(header_data)
  end
  defp extract_header(_), do: {:error, :invalid_header}

  defp validate_and_build_header(header_data) do
    with {:ok, index} <- extract_integer(header_data, ["index", :index]),
         {:ok, previous_hash} <- extract_hash_field(header_data, ["previous_hash", :previous_hash]),
         {:ok, merkle_root} <- extract_hash_field(header_data, ["merkle_root", :merkle_root]),
         {:ok, timestamp} <- extract_integer(header_data, ["timestamp", :timestamp]),
         {:ok, nonce} <- extract_integer(header_data, ["nonce", :nonce]),
         {:ok, difficulty} <- extract_integer(header_data, ["difficulty", :difficulty]),
         {:ok, consensus_data} <- extract_consensus_field(header_data) do

      header = %{
        index: index,
        previous_hash: previous_hash,
        merkle_root: merkle_root,
        timestamp: timestamp,
        nonce: nonce,
        difficulty: difficulty,
        consensus_data: consensus_data
      }

      {:ok, header}
    else
      error -> error
    end
  end

  # Extraction and validation of transactions
  defp extract_transactions(%{"transactions" => txs}) when is_list(txs) do
    convert_transaction_list(txs)
  end
  defp extract_transactions(%{transactions: txs}) when is_list(txs) do
    convert_transaction_list(txs)
  end
  defp extract_transactions(_), do: {:error, :invalid_transactions}

  defp convert_transaction_list(transaction_list) do
    transaction_list
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {tx_data, index}, {:ok, acc} ->
      case convert_transaction(tx_data, index) do
        {:ok, tx} -> {:cont, {:ok, [tx | acc]}}
        {:error, reason} -> {:halt, {:error, {:transaction_error, index, reason}}}
      end
    end)
    |> case do
      {:ok, transactions} -> {:ok, Enum.reverse(transactions)}
      error -> error
    end
  end

  defp convert_transaction(tx_data, index) when is_map(tx_data) do
    with {:ok, from} <- extract_string(tx_data, ["from", :from]),
         {:ok, to} <- extract_string(tx_data, ["to", :to]),
         {:ok, amount} <- extract_integer(tx_data, ["amount", :amount]),
         {:ok, fee} <- extract_integer(tx_data, ["fee", :fee]),
         {:ok, nonce} <- extract_integer(tx_data, ["nonce", :nonce]),
         {:ok, timestamp} <- extract_integer(tx_data, ["timestamp", :timestamp]),
         {:ok, hash} <- extract_hash_field(tx_data, ["hash", :hash]),
         {:ok, signature_type} <- extract_signature_type(tx_data),
         {:ok, data} <- extract_string_optional(tx_data, ["data", :data]),
         {:ok, signature} <- extract_signature_field(tx_data) do

      transaction = %Bastille.Features.Transaction.Transaction{
        from: from,
        to: to,
        amount: amount,
        fee: fee,
        nonce: nonce,
        timestamp: timestamp,
        hash: hash,
        signature_type: signature_type,
        signature: signature,
        data: data || ""
      }

      {:ok, transaction}
    else
      {:error, reason} -> {:error, {:invalid_transaction_field, index, reason}}
    end
  end

  defp convert_transaction(_, index), do: {:error, {:invalid_transaction_data, index}}

  # Extraction helpers
  defp extract_integer(data, keys) do
    case find_value(data, keys) do
      value when is_integer(value) -> {:ok, value}
      value when is_binary(value) ->
        case Integer.parse(value) do
          {int, ""} -> {:ok, int}
          _ -> {:error, {:invalid_integer, value}}
        end
      _ -> {:error, :missing_integer}
    end
  end

  defp extract_string(data, keys) do
    case find_value(data, keys) do
      value when is_binary(value) and byte_size(value) > 0 -> {:ok, value}
      _ -> {:error, :missing_string}
    end
  end

  defp extract_string_optional(data, keys) do
    case find_value(data, keys) do
      value when is_binary(value) -> {:ok, value}
      nil -> {:ok, nil}
      _ -> {:error, :invalid_string}
    end
  end

  defp extract_hash_field(data, keys) do
    case find_value(data, keys) do
      hash when is_binary(hash) and byte_size(hash) == 32 -> {:ok, hash}
      hex when is_binary(hex) ->
        case Base.decode16(hex, case: :mixed) do
          {:ok, hash} when byte_size(hash) == 32 -> {:ok, hash}
          _ -> {:error, {:invalid_hex_hash, hex}}
        end
      _ -> {:error, :missing_hash}
    end
  end

  # Extract consensus_data (strict: no typo tolerance)
  defp extract_consensus_field(data) do
    value = Map.get(data, "consensus_data")

    cond do
      is_map(value) -> {:ok, value}
      is_binary(value) ->
        try do
          {:ok, :erlang.binary_to_term(value)}
        rescue
          _ -> {:ok, %{}}
        end
      true -> {:ok, %{}}
    end
  end

  defp extract_signature_type(data) do
    case find_value(data, ["signature_type", :signature_type]) do
      "coinbase" -> {:ok, :coinbase}
      :coinbase -> {:ok, :coinbase}
      "regular" -> {:ok, :regular}
      :regular -> {:ok, :regular}
      nil -> {:ok, :regular}  # Default
      other -> {:error, {:invalid_signature_type, other}}
    end
  end

  defp extract_signature_field(data) do
    value = find_value(data, ["signature", :signature])
    cond do
      is_map(value) -> {:ok, value}
      is_binary(value) ->
        try do
          {:ok, :erlang.binary_to_term(value)}
        rescue
          _ -> {:ok, nil}
        end
      true -> {:ok, nil}
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
