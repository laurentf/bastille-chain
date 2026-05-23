defmodule Bastille.Features.Api.RPC.CreateUnsignedTransaction do
  @moduledoc """
  Creates an unsigned transaction ready for offline signing.

  Returns a JSON-safe map (NOT base64-encoded ETF). Consumers should never
  invoke `:erlang.binary_to_term/1` on RPC input — see
  `Bastille.Features.Transaction.Transaction.to_json_map/1` for the
  canonical wire format.

  ## Web3-style wallet flow
  1. `create_unsigned_transaction` → unsigned tx as a JSON map
  2. Wallet signs offline (or via `sign_transaction` in dev/test)
  3. `submit_transaction` accepts the signed JSON map and broadcasts it
  """

  require Logger

  alias Bastille.Features.Chain.Chain
  alias Bastille.Features.Tokenomics.Token
  alias Bastille.Features.Transaction.Transaction
  alias Bastille.Shared.Address

  def call(params) do
    from = params["from"] || params["from_address"]
    to = params["to"] || params["to_address"]
    amount = params["amount"]
    data = params["data"] || <<>>
    # Note: `fee` from params is intentionally ignored. `Transaction.new/1`
    # always derives the fee from tx size to prevent clients underpaying
    # the mempool floor or overpaying by mistake.

    case create_unsigned(from, to, amount, data) do
      {:ok, unsigned_tx} ->
        Logger.info("📝 Unsigned tx prepared")
        Logger.info("   └─ from: #{unsigned_tx.from}")
        Logger.info("   └─ to: #{unsigned_tx.to}")
        Logger.info("   └─ amount: #{unsigned_tx.amount} juillet, fee: #{unsigned_tx.fee} juillet")
        Logger.info("   └─ hash: #{Base.encode16(unsigned_tx.hash, case: :lower) |> String.slice(0, 16)}...")

        # Flat: the RPC dispatcher already wraps the return value under `result:`.
        %{
          "unsigned_transaction" => Transaction.to_json_map(unsigned_tx),
          "transaction_hash" => Base.encode16(unsigned_tx.hash, case: :lower)
        }

      {:error, reason} ->
        rpc_error(-32_602, "Transaction creation failed: #{inspect(reason)}")
    end
  rescue
    error -> rpc_error(-32_602, "Failed to create transaction: #{Exception.message(error)}")
  end

  defp create_unsigned(from, to, amount, data) when is_binary(from) and is_binary(to) do
    with :ok <- Bastille.validate_address(from),
         :ok <- Bastille.validate_address(to),
         {:ok, amount_juillet} <- coerce_amount(amount),
         {:ok, data_bin} <- coerce_data(data) do
      from_canonical = Address.canonical(from)
      to_canonical = Address.canonical(to)

      unsigned_tx =
        Transaction.new(
          from: from_canonical,
          to: to_canonical,
          amount: amount_juillet,
          nonce: Chain.get_nonce(from_canonical) + 1,
          data: data_bin,
          signature_type: :post_quantum_2_of_3
        )

      {:ok, unsigned_tx}
    end
  end

  defp create_unsigned(_, _, _, _), do: {:error, :missing_address}

  defp coerce_amount(v) when is_integer(v) and v > 0, do: {:ok, v}
  defp coerce_amount(v) when is_float(v) and v > 0, do: {:ok, Token.bast_to_juillet(v)}
  defp coerce_amount(_), do: {:error, :invalid_amount}

  defp coerce_data(v) when is_binary(v), do: {:ok, v}
  defp coerce_data(nil), do: {:ok, <<>>}
  defp coerce_data(_), do: {:error, :invalid_data}

  defp rpc_error(code, message) do
    %{"error" => %{"code" => code, "message" => message}}
  end
end
