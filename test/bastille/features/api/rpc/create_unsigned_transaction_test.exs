defmodule Bastille.Features.Api.RPC.CreateUnsignedTransactionTest do
  use ExUnit.Case, async: true

  alias Bastille.Features.Api.RPC.CreateUnsignedTransaction
  alias Bastille.Features.Transaction.Transaction

  @moduletag :unit

  defp valid_from, do: "f789" <> String.duplicate("a", 40)
  defp valid_to, do: "f789" <> String.duplicate("b", 40)

  describe "input validation" do
    test "rejects missing parameters" do
      assert %{"error" => %{"code" => -32_602}} = CreateUnsignedTransaction.call(%{})
    end

    test "rejects missing 'from'" do
      result = CreateUnsignedTransaction.call(%{"to" => valid_to(), "amount" => 1000})
      assert match?(%{"error" => %{"code" => -32_602}}, result)
    end

    test "rejects missing 'to'" do
      result = CreateUnsignedTransaction.call(%{"from" => valid_from(), "amount" => 1000})
      assert match?(%{"error" => %{"code" => -32_602}}, result)
    end

    test "rejects missing 'amount'" do
      result = CreateUnsignedTransaction.call(%{"from" => valid_from(), "to" => valid_to()})
      assert match?(%{"error" => %{"code" => -32_602}}, result)
    end

    test "rejects invalid address formats" do
      invalids = [
        "invalid_address",
        "1234short",
        "wrongprefix" <> String.duplicate("a", 40)
      ]

      for bad <- invalids do
        result = CreateUnsignedTransaction.call(%{
          "from" => bad,
          "to" => valid_to(),
          "amount" => 1000
        })

        assert match?(%{"error" => _}, result), "Expected error for #{bad}"
      end
    end

    test "rejects non-positive amounts" do
      for bad <- [-100, 0, "not_a_number", nil] do
        result = CreateUnsignedTransaction.call(%{
          "from" => valid_from(),
          "to" => valid_to(),
          "amount" => bad
        })

        assert match?(%{"error" => _}, result), "Expected error for amount=#{inspect(bad)}"
      end
    end
  end

  describe "successful response" do
    test "returns a JSON-safe map for the unsigned transaction (no base64+ETF)" do
      result =
        CreateUnsignedTransaction.call(%{
          "from" => valid_from(),
          "to" => valid_to(),
          "amount" => 1_000_000
        })

      assert %{"unsigned_transaction" => tx_map, "transaction_hash" => hash_hex} = result

      # tx_map is a plain map, NOT a base64 string
      assert is_map(tx_map)
      refute is_binary(tx_map)

      # All expected fields present
      assert tx_map["from"] == valid_from()
      assert tx_map["to"] == valid_to()
      assert tx_map["amount"] == 1_000_000
      assert is_integer(tx_map["fee"]) and tx_map["fee"] > 0
      assert is_integer(tx_map["nonce"]) and tx_map["nonce"] >= 0
      assert is_integer(tx_map["timestamp"])
      assert tx_map["signature_type"] == "post_quantum_2_of_3"
      assert is_binary(tx_map["hash"]) and String.length(tx_map["hash"]) == 64

      # Top-level hash matches the inner one
      assert hash_hex == tx_map["hash"]

      # No signature on an unsigned tx
      refute Map.has_key?(tx_map, "signature")
    end

    test "the unsigned map round-trips through Transaction.from_json_map" do
      %{"unsigned_transaction" => tx_map} =
        CreateUnsignedTransaction.call(%{
          "from" => valid_from(),
          "to" => valid_to(),
          "amount" => 5_000_000
        })

      assert {:ok, %Transaction{} = tx} = Transaction.from_json_map(tx_map)
      assert tx.from == valid_from()
      assert tx.to == valid_to()
      assert tx.amount == 5_000_000
      assert tx.signature == nil
    end

    test "accepts checksummed mixed-case addresses (and canonicalizes them)" do
      checksummed_from = Bastille.Shared.Address.with_checksum(valid_from())

      %{"unsigned_transaction" => tx_map} =
        CreateUnsignedTransaction.call(%{
          "from" => checksummed_from,
          "to" => valid_to(),
          "amount" => 1_000_000
        })

      # Stored canonical (lowercase) on chain regardless of input case
      assert tx_map["from"] == valid_from()
    end

    test "ignores client-supplied fee and uses size-based auto fee" do
      %{"unsigned_transaction" => tx_map} =
        CreateUnsignedTransaction.call(%{
          "from" => valid_from(),
          "to" => valid_to(),
          "amount" => 1_000_000,
          "fee" => 1
        })

      # Even though the client passed fee=1, the server recomputes from
      # tx size — preventing under-fee mempool spam.
      assert tx_map["fee"] > 1
    end
  end
end
