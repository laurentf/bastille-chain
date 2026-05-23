defmodule Bastille.Features.Api.RPC.GetTransaction do
  @moduledoc """
  Look up a transaction by hash.

  Resolution order:
  1. **Mempool** — the tx is pending inclusion in a block.
     Response: `status: "pending"`, no block info.
  2. **Confirmed index** (`index.cubdb`) — the tx has been included in a
     block.  Response: `status: "confirmed"`, plus `block_hash`,
     `block_height`, `confirmations` (>= 1).
  3. Otherwise → `status: "not_found"`.

  The transaction itself is returned as the canonical JSON map shape (see
  `Transaction.to_json_map/1`) — same format produced by
  `create_unsigned_transaction` / `sign_transaction`, so wallets only have
  to handle one shape.
  """

  require Logger

  alias Bastille.Features.Chain.Chain
  alias Bastille.Features.Transaction.{Mempool, Transaction}
  alias Bastille.Infrastructure.Storage.CubDB.{Blocks, Index}

  def call(%{"hash" => hex_hash}) when is_binary(hex_hash) do
    case Base.decode16(hex_hash, case: :mixed) do
      {:ok, hash_bin} when byte_size(hash_bin) == 32 ->
        lookup(hash_bin, hex_hash)

      _ ->
        %{error: "Invalid transaction hash (expected 64-char hex)"}
    end
  rescue
    error -> %{error: Exception.message(error)}
  end

  def call(_), do: %{error: "Missing or invalid 'hash' parameter"}

  defp lookup(hash_bin, hex_hash) do
    case Mempool.get_transaction(hash_bin) do
      %Transaction{} = tx ->
        Logger.debug("🔍 Tx #{short(hex_hash)} found in mempool")
        pending_response(tx)

      _ ->
        lookup_in_index(hash_bin, hex_hash)
    end
  end

  defp lookup_in_index(hash_bin, hex_hash) do
    case Index.find_transaction(hash_bin) do
      {:ok, {partition, block_hash, tx_index}} ->
        load_confirmed(hash_bin, hex_hash, partition, block_hash, tx_index)

      {:error, :not_found} ->
        Logger.debug("🔍 Tx #{short(hex_hash)} not found")
        %{status: "not_found", hash: hex_hash}
    end
  end

  defp load_confirmed(_hash_bin, hex_hash, partition, block_hash, tx_index) do
    with {:ok, block} <- Blocks.get_block_from_partition(block_hash, partition),
         tx when not is_nil(tx) <- Enum.at(block.transactions, tx_index) do
      current_height = Chain.get_height()
      confirmations = max(0, current_height - block.header.index + 1)

      Logger.debug("🔍 Tx #{short(hex_hash)} confirmed at height #{block.header.index} (#{confirmations} confirmations)")

      %{
        status: "confirmed",
        hash: hex_hash,
        confirmations: confirmations,
        block_height: block.header.index,
        block_hash: Base.encode16(block.hash, case: :lower),
        transaction: Transaction.to_json_map(tx)
      }
    else
      # Index points to a block/tx that storage can no longer materialize.
      # Should be rare (only on partition rotation bugs or partial restore).
      _ ->
        Logger.warning("⚠️ Tx #{short(hex_hash)} indexed but block/tx missing (partition #{partition})")
        %{status: "not_found", hash: hex_hash, note: "index entry could not be resolved"}
    end
  end

  defp pending_response(%Transaction{} = tx) do
    %{
      status: "pending",
      hash: Base.encode16(tx.hash, case: :lower),
      transaction: Transaction.to_json_map(tx)
    }
  end

  defp short(hex), do: String.slice(hex, 0, 16)
end
