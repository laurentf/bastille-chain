defmodule Bastille.Features.Api.RPC.SignTransactionTest do
  use ExUnit.Case, async: true

  alias Bastille.Features.Api.RPC.SignTransaction
  alias Bastille.Features.Transaction.Transaction
  alias Bastille.Shared.Crypto

  @moduletag :unit

  defp valid_unsigned_map do
    tx =
      Transaction.new(
        from: "f789" <> String.duplicate("a", 40),
        to: "f789" <> String.duplicate("b", 40),
        amount: 1_000_000,
        nonce: 1
      )

    Transaction.to_json_map(tx)
  end

  defp random_key_b64(size_bits) do
    Base.encode64(<<0::size(size_bits)>>)
  end

  describe "input validation" do
    test "rejects missing parameters" do
      assert %{"error" => %{"code" => -32_602, "message" => msg}} = SignTransaction.call(%{})
      assert msg =~ "unsigned_transaction" or msg =~ "Invalid parameters"
    end

    test "rejects missing unsigned_transaction" do
      result =
        SignTransaction.call(%{
          "dilithium_key" => random_key_b64(2560 * 8),
          "falcon_key" => random_key_b64(1281 * 8),
          "sphincs_key" => random_key_b64(64 * 8)
        })

      assert %{"error" => _} = result
    end

    test "rejects missing private keys" do
      result =
        SignTransaction.call(%{
          "unsigned_transaction" => valid_unsigned_map()
        })

      assert %{"error" => %{"message" => msg}} = result
      assert msg =~ "dilithium_key" or msg =~ "Invalid parameters"
    end

    test "rejects a base64+ETF unsigned_transaction (security regression)" do
      # The old API accepted base64-encoded ETF. The new API must reject.
      legacy_payload =
        Base.encode64(
          :erlang.term_to_binary(%{
            from: "1789abc",
            to: "1789def",
            amount: 1000,
            nonce: 1
          })
        )

      result =
        SignTransaction.call(%{
          "unsigned_transaction" => legacy_payload,
          "dilithium_key" => random_key_b64(2560 * 8),
          "falcon_key" => random_key_b64(1281 * 8),
          "sphincs_key" => random_key_b64(64 * 8)
        })

      assert %{"error" => %{"message" => msg}} = result
      assert msg =~ ~r/json object|invalid/i
    end

    test "rejects invalid base64 in private keys" do
      result =
        SignTransaction.call(%{
          "unsigned_transaction" => valid_unsigned_map(),
          "dilithium_key" => "not!valid?base64",
          "falcon_key" => random_key_b64(1281 * 8),
          "sphincs_key" => random_key_b64(64 * 8)
        })

      assert %{"error" => %{"message" => msg}} = result
      assert msg =~ "base64" or msg =~ "Invalid"
    end

    test "rejects keys with wrong sizes" do
      result =
        SignTransaction.call(%{
          "unsigned_transaction" => valid_unsigned_map(),
          # Wrong sizes
          "dilithium_key" => Base.encode64(<<0::8>>),
          "falcon_key" => Base.encode64(<<0::8>>),
          "sphincs_key" => Base.encode64(<<0::8>>)
        })

      assert %{"error" => %{"message" => msg}} = result
      assert msg =~ "key sizes" or msg =~ "Invalid"
    end
  end

  describe "happy path (with a real keypair stored)" do
    test "signs an unsigned transaction whose sender pubkeys are stored" do
      # 1. Generate a real PQ keypair, store the pubkeys against the
      #    derived address (mimics what generate_address does).
      kp = Crypto.generate_pq_keypair()
      Crypto.store_public_keys_from_keypair(kp)
      from_addr = Crypto.generate_bastille_address(kp)

      # 2. Build an unsigned tx from that address.
      tx =
        Transaction.new(
          from: from_addr,
          to: "f789" <> String.duplicate("b", 40),
          amount: 1_000_000,
          nonce: 1
        )

      unsigned_map = Transaction.to_json_map(tx)

      result =
        SignTransaction.call(%{
          "unsigned_transaction" => unsigned_map,
          "dilithium_key" => Base.encode64(kp.dilithium.private),
          "falcon_key" => Base.encode64(kp.falcon.private),
          "sphincs_key" => Base.encode64(kp.sphincs.private)
        })

      assert %{"signed_transaction" => signed_map, "transaction_hash" => hash} = result

      assert is_map(signed_map)
      assert is_binary(hash)
      assert String.length(hash) == 64

      assert Map.has_key?(signed_map, "signature")
      assert %{"dilithium" => _, "falcon" => _, "sphincs" => _} = signed_map["signature"]

      # Round-trip through from_json_map and confirm the signature verifies.
      assert {:ok, signed_tx} = Transaction.from_json_map(signed_map)
      assert Transaction.verify_signature(signed_tx)
    end

    test "rejects signing when private keys do not match the sender address" do
      kp_a = Crypto.generate_pq_keypair()
      Crypto.store_public_keys_from_keypair(kp_a)
      from_addr_a = Crypto.generate_bastille_address(kp_a)

      # Different keypair, NOT stored: try to sign for `from_addr_a`
      kp_b = Crypto.generate_pq_keypair()

      tx =
        Transaction.new(
          from: from_addr_a,
          to: "f789" <> String.duplicate("b", 40),
          amount: 1_000,
          nonce: 1
        )

      result =
        SignTransaction.call(%{
          "unsigned_transaction" => Transaction.to_json_map(tx),
          "dilithium_key" => Base.encode64(kp_b.dilithium.private),
          "falcon_key" => Base.encode64(kp_b.falcon.private),
          "sphincs_key" => Base.encode64(kp_b.sphincs.private)
        })

      assert %{"error" => %{"message" => msg}} = result
      assert msg =~ "sender" or msg =~ "do not match"
    end
  end
end
