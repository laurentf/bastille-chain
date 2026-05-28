defmodule Bastille.Features.Transaction.TransactionConverterTest do
  use ExUnit.Case, async: true

  alias Bastille.Features.Transaction.{Transaction, TransactionConverter}
  alias Bastille.Features.P2P.Messaging.{Codec, Messages}

  @moduletag :unit

  defp addr do
    prefix = Application.get_env(:bastille, :address_prefix, "f789")
    prefix <> String.duplicate("a", 40)
  end

  defp sample_tx do
    %Transaction{
      from: addr(),
      to: addr(),
      amount: 1000,
      fee: 10,
      nonce: 3,
      timestamp: 1_700_000_000,
      data: "hello",
      signature: %{dilithium: <<1, 2, 3>>, falcon: <<4, 5>>, sphincs: <<6>>},
      signature_type: :regular,
      hash: :crypto.strong_rand_bytes(32)
    }
  end

  defp base_map(tx) do
    %{
      "from" => tx.from,
      "to" => tx.to,
      "amount" => tx.amount,
      "fee" => tx.fee,
      "nonce" => tx.nonce,
      "timestamp" => tx.timestamp,
      "data" => tx.data,
      "signature" => tx.signature,
      "signature_type" => "regular",
      "hash" => tx.hash
    }
  end

  describe "from_p2p_data/1" do
    test "rebuilds a transaction from a valid string-keyed map" do
      tx = sample_tx()

      assert {:ok, converted} = TransactionConverter.from_p2p_data(base_map(tx))
      assert converted.from == tx.from
      assert converted.to == tx.to
      assert converted.amount == tx.amount
      assert converted.hash == tx.hash
      assert converted.signature_type == :regular
      assert converted.data == "hello"
    end

    test "defaults a missing data field to an empty string" do
      data = base_map(sample_tx()) |> Map.delete("data")
      assert {:ok, %Transaction{data: ""}} = TransactionConverter.from_p2p_data(data)
    end

    test "rejects a hash that is not 32 bytes" do
      data = base_map(sample_tx()) |> Map.put("hash", <<0, 1, 2>>)
      assert {:error, :invalid_hash} = TransactionConverter.from_p2p_data(data)
    end

    test "rejects an invalid address" do
      data = base_map(sample_tx()) |> Map.put("from", "not-an-address")
      assert {:error, {:invalid_address, _}} = TransactionConverter.from_p2p_data(data)
    end

    test "rejects a negative amount" do
      data = base_map(sample_tx()) |> Map.put("amount", -5)
      assert {:error, {:invalid_integer, "amount"}} = TransactionConverter.from_p2p_data(data)
    end

    test "rejects an unknown signature_type" do
      data = base_map(sample_tx()) |> Map.put("signature_type", "bogus")

      assert {:error, {:invalid_signature_type, "bogus"}} =
               TransactionConverter.from_p2p_data(data)
    end

    test "accepts the post_quantum_2_of_3 type the real signer emits" do
      # Regression: a live multinode run showed RPC-signed user txs were rejected
      # on arrival (only "regular"/"coinbase" were whitelisted), so signed txs
      # could not propagate between nodes.
      data = base_map(sample_tx()) |> Map.put("signature_type", "post_quantum_2_of_3")

      assert {:ok, %Transaction{signature_type: :post_quantum_2_of_3}} =
               TransactionConverter.from_p2p_data(data)
    end

    test "rejects non-map input" do
      assert {:error, :invalid_transaction_data} = TransactionConverter.from_p2p_data("nope")
    end
  end

  describe "P2P wire roundtrip" do
    test "a transaction survives tx_message -> encode -> decode -> converter unchanged" do
      tx = sample_tx()

      payload = Messages.tx_message(tx)[:tx]
      {:ok, frame} = Codec.encode(:tx, payload)
      {:ok, {:tx, decoded_map}} = Codec.decode(IO.iodata_to_binary(frame))

      assert {:ok, converted} = TransactionConverter.from_p2p_data(decoded_map)
      assert converted.from == tx.from
      assert converted.to == tx.to
      assert converted.amount == tx.amount
      assert converted.fee == tx.fee
      assert converted.nonce == tx.nonce
      assert converted.timestamp == tx.timestamp
      assert converted.data == tx.data
      assert converted.signature == tx.signature
      assert converted.signature_type == tx.signature_type
      assert converted.hash == tx.hash
    end
  end
end
