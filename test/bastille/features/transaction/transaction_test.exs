defmodule Bastille.Features.Transaction.TransactionTest do
  use ExUnit.Case, async: false  # Some tests mutate Application env (network/chain_id)
  alias Bastille.Features.Transaction.Transaction
  alias Bastille.Features.Tokenomics.Token
  alias Bastille.Shared.Crypto

  @moduletag :unit

  describe "transaction structure and validation" do
    test "creates transaction with basic fields" do
      tx = Transaction.new([
        from: "f789sender123456789",
        to: "f789receiver123456789",
        amount: Token.bast_to_juillet(1.0),
        nonce: 1
      ])

      assert tx.from == "f789sender123456789"
      assert tx.to == "f789receiver123456789"
      assert tx.amount == Token.bast_to_juillet(1.0)
      assert is_integer(tx.fee)
      assert tx.fee > 0
      assert tx.nonce == 1
      assert is_integer(tx.timestamp)
      assert is_binary(tx.hash)
    end

    test "validates required transaction fields" do
      required_fields = [:from, :to, :amount, :fee, :nonce]

      tx = Transaction.new([
        from: "f789from123",
        to: "f789to456",
        amount: 1000,
        nonce: 1
      ])

      for field <- required_fields do
        assert Map.has_key?(tx, field)
        assert Map.get(tx, field) != nil
      end
    end

    test "handles different transaction amounts" do
      # Test various BAST amounts
      amounts = [
        Token.bast_to_juillet(0.001),   # Small amount
        Token.bast_to_juillet(1.0),     # 1 BAST
        Token.bast_to_juillet(100.0),   # Large amount
        Token.bast_to_juillet(1789.0)   # Revolutionary amount
      ]

      for amount <- amounts do
        tx = Transaction.new([
          from: "f789test123",
          to: "f789test456",
          amount: amount,
          nonce: 1
        ])

        assert tx.amount == amount
        assert tx.amount > 0
      end
    end

    test "validates automatic fee calculation" do
      base_amount = Token.bast_to_juillet(1.0)

      tx = Transaction.new([
        from: "f789sender",
        to: "f789receiver",
        amount: base_amount,
        nonce: 1
      ])

      # Fee should be automatically calculated based on transaction size
      assert is_integer(tx.fee)
      assert tx.fee > 0
      assert tx.fee < tx.amount  # Fee should be less than amount

      # Fee should be at least the minimum fee
      min_fee = 100_000  # 0.001 BAST minimum
      assert tx.fee >= min_fee
    end
  end

  describe "transaction hashing and determinism" do
    test "calculates consistent hash for same transaction data" do
      tx_data = [
        from: "f789consistent",
        to: "f789test",
        amount: Token.bast_to_juillet(1.0),
        nonce: 1,
        timestamp: 1234567890
      ]

      tx1 = Transaction.new(tx_data)
      tx2 = Transaction.new(tx_data)

      assert tx1.hash == tx2.hash
      assert byte_size(tx1.hash) == 32
    end

    test "different transaction data produces different hashes" do
      tx1 = Transaction.new([
        from: "f789sender1",
        to: "f789receiver1",
        amount: Token.bast_to_juillet(1.0),
        nonce: 1
      ])

      tx2 = Transaction.new([
        from: "f789sender2",
        to: "f789receiver2",
        amount: Token.bast_to_juillet(1.0),
        nonce: 1
      ])

      assert tx1.hash != tx2.hash
      assert byte_size(tx1.hash) == 32
      assert byte_size(tx2.hash) == 32
    end

    test "nonce changes affect transaction hash" do
      base_data = [
        from: "f789sender",
        to: "f789receiver",
        amount: Token.bast_to_juillet(1.0)
      ]

      tx1 = Transaction.new(base_data ++ [nonce: 1])
      tx2 = Transaction.new(base_data ++ [nonce: 2])

      assert tx1.hash != tx2.hash
      assert tx1.nonce != tx2.nonce
    end
  end

  describe "transaction amounts and precision" do
    test "handles BAST decimal precision correctly" do
      # BAST has specific precision requirements
      one_bast = Token.bast_to_juillet(1.0)
      half_bast = Token.bast_to_juillet(0.5)
      quarter_bast = Token.bast_to_juillet(0.25)

      assert one_bast > half_bast
      assert half_bast > quarter_bast
      assert one_bast == half_bast * 2
      assert half_bast == quarter_bast * 2
    end

    test "validates minimum transaction amounts" do
      min_amount = 1  # 1 smallest unit

      tx = Transaction.new([
        from: "f789min_test",
        to: "f789min_receiver",
        amount: min_amount,
        fee: Token.bast_to_juillet(0.001),
        nonce: 1
      ])

      assert tx.amount == min_amount
      assert tx.amount > 0
    end

    test "calculates total transaction cost" do
      amount = Token.bast_to_juillet(1.0)

      tx = Transaction.new([
        from: "f789cost_test",
        to: "f789cost_receiver",
        amount: amount,
        nonce: 1
      ])

      total_cost = tx.amount + tx.fee
      assert total_cost > tx.amount
      assert total_cost > tx.fee
      assert is_integer(total_cost)
    end
  end

  describe "serialize_for_signing — message integrity" do
    # The message signed by Crypto.sign/2 MUST cover all fields whose
    # modification by a network attacker could harm the sender. Historically
    # `fee` and `data` were NOT covered: this regression test ensures they
    # are part of the signed payload going forward.

    setup do
      base_opts = [
        from: "f789" <> String.duplicate("a", 40),
        to: "f789" <> String.duplicate("b", 40),
        amount: 1_000_000,
        nonce: 1,
        timestamp: 1_700_000_000,
        data: "original payload"
      ]

      tx = Transaction.new(base_opts)
      {:ok, tx: tx, base_opts: base_opts}
    end

    test "is deterministic for identical input", %{tx: tx} do
      assert Transaction.serialize_for_signing(tx) ==
               Transaction.serialize_for_signing(tx)
    end

    test "differs when fee differs", %{tx: tx} do
      msg_a = Transaction.serialize_for_signing(tx)
      msg_b = Transaction.serialize_for_signing(%{tx | fee: tx.fee + 1})
      assert msg_a != msg_b
    end

    test "differs when data differs", %{tx: tx} do
      msg_a = Transaction.serialize_for_signing(tx)
      msg_b = Transaction.serialize_for_signing(%{tx | data: tx.data <> "x"})
      assert msg_a != msg_b
    end

    test "differs across chain_ids (testnet vs mainnet)", %{tx: tx} do
      original = Application.get_env(:bastille, :network)

      Application.put_env(:bastille, :network, :testnet)
      msg_testnet = Transaction.serialize_for_signing(tx)

      Application.put_env(:bastille, :network, :mainnet)
      msg_mainnet = Transaction.serialize_for_signing(tx)

      assert msg_testnet != msg_mainnet

      Application.put_env(:bastille, :network, original)
    end

    test "differs when amount/nonce/timestamp differ (existing protection still in place)", %{tx: tx} do
      msg = Transaction.serialize_for_signing(tx)

      assert msg != Transaction.serialize_for_signing(%{tx | amount: tx.amount + 1})
      assert msg != Transaction.serialize_for_signing(%{tx | nonce: tx.nonce + 1})
      assert msg != Transaction.serialize_for_signing(%{tx | timestamp: tx.timestamp + 1})
    end

    test "end-to-end: tampering fee after signing breaks the 2/3 PQ signature", %{tx: tx} do
      # Sign with a real PQ keypair, then verify directly via Crypto (bypasses
      # State.get_public_keys to keep this a pure unit test).
      kp = Crypto.generate_pq_keypair()
      signed = Transaction.sign(tx, kp)

      pubs = %{
        dilithium: kp.dilithium.public,
        falcon: kp.falcon.public,
        sphincs: kp.sphincs.public
      }

      assert Crypto.verify(Transaction.serialize_for_signing(signed), signed.signature, pubs)

      tampered = %{signed | fee: signed.fee + 1}

      refute Crypto.verify(Transaction.serialize_for_signing(tampered), tampered.signature, pubs)
    end

    test "end-to-end: tampering data after signing breaks the 2/3 PQ signature", %{tx: tx} do
      kp = Crypto.generate_pq_keypair()
      signed = Transaction.sign(tx, kp)

      pubs = %{
        dilithium: kp.dilithium.public,
        falcon: kp.falcon.public,
        sphincs: kp.sphincs.public
      }

      tampered = %{signed | data: signed.data <> <<0>>}

      refute Crypto.verify(Transaction.serialize_for_signing(tampered), tampered.signature, pubs)
    end

    test "end-to-end: a signature minted on testnet does not verify on mainnet", %{tx: tx} do
      original = Application.get_env(:bastille, :network)

      Application.put_env(:bastille, :network, :testnet)
      kp = Crypto.generate_pq_keypair()
      signed_on_testnet = Transaction.sign(tx, kp)

      pubs = %{
        dilithium: kp.dilithium.public,
        falcon: kp.falcon.public,
        sphincs: kp.sphincs.public
      }

      # Same tx, same signature, but verifier is now on mainnet → message bytes differ → rejected.
      Application.put_env(:bastille, :network, :mainnet)
      message_as_seen_by_mainnet = Transaction.serialize_for_signing(signed_on_testnet)
      refute Crypto.verify(message_as_seen_by_mainnet, signed_on_testnet.signature, pubs)

      Application.put_env(:bastille, :network, original)
    end
  end

  describe "transaction serialization" do
    test "serializes transaction to consistent binary format" do
      tx = Transaction.new([
        from: "f789serialize",
        to: "f789binary",
        amount: Token.bast_to_juillet(1.0),
        fee: Token.bast_to_juillet(0.001),
        nonce: 1
      ])

      # Test that we can serialize (mock implementation)
      serialized = :erlang.term_to_binary(tx)
      deserialized = :erlang.binary_to_term(serialized)

      assert is_binary(serialized)
      assert deserialized.from == tx.from
      assert deserialized.to == tx.to
      assert deserialized.amount == tx.amount
      assert deserialized.fee == tx.fee
    end

    test "serialization is deterministic" do
      tx_data = [
        from: "f789deterministic",
        to: "f789test",
        amount: Token.bast_to_juillet(1.0),
        fee: Token.bast_to_juillet(0.001),
        nonce: 1,
        timestamp: 1234567890
      ]

      tx = Transaction.new(tx_data)

      binary1 = :erlang.term_to_binary(tx)
      binary2 = :erlang.term_to_binary(tx)

      assert binary1 == binary2
    end
  end

  describe "nonce and replay protection" do
    test "handles transaction nonces correctly" do
      base_data = [
        from: "f789nonce_test",
        to: "f789nonce_receiver",
        amount: Token.bast_to_juillet(1.0),
        fee: Token.bast_to_juillet(0.001)
      ]

      tx1 = Transaction.new(base_data ++ [nonce: 1])
      tx2 = Transaction.new(base_data ++ [nonce: 2])
      tx3 = Transaction.new(base_data ++ [nonce: 3])

      assert tx1.nonce < tx2.nonce
      assert tx2.nonce < tx3.nonce
      assert tx2.nonce == tx1.nonce + 1
      assert tx3.nonce == tx2.nonce + 1
    end

    test "validates nonce sequencing" do
      nonces = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

      transactions = Enum.map(nonces, fn nonce ->
        Transaction.new([
          from: "f789sequence",
          to: "f789test",
          amount: Token.bast_to_juillet(1.0),
          nonce: nonce
        ])
      end)

      # Verify nonces are in sequence
      for i <- 1..(length(transactions) - 1) do
        current = Enum.at(transactions, i - 1)
        next = Enum.at(transactions, i)
        assert next.nonce == current.nonce + 1
      end
    end
  end

  describe "French Revolution themed transactions" do
    test "handles revolutionary transaction amounts" do
      revolutionary_amounts = [
        Token.bast_to_juillet(17.89),    # Year reference
        Token.bast_to_juillet(1789.0),   # Full year
        Token.bast_to_juillet(14.7),     # Bastille Day reference
      ]

      for amount <- revolutionary_amounts do
        tx = Transaction.new([
          from: "f789revolution",
          to: "f789liberte",
          amount: amount,
          nonce: 1,
          data: "Liberté, Égalité, Fraternité!"
        ])

        assert tx.amount == amount
        assert tx.amount > 0
        if Map.has_key?(tx, :data), do: assert(tx.data =~ ~r/Liberté/)
      end
    end

    test "supports revolutionary addresses" do
      addresses = [
        "f789LiberteRevolutionAddress",
        "f789EgaliteRepublicAddress",
        "f789FraterniteBastilleAddr"
      ]

      for {from_addr, to_addr} <- Enum.zip(addresses, Enum.reverse(addresses)) do
        tx = Transaction.new([
          from: from_addr,
          to: to_addr,
          amount: Token.bast_to_juillet(1789.0),
          nonce: 1
        ])

        assert String.starts_with?(tx.from, "f789")
        assert String.starts_with?(tx.to, "f789")
        assert tx.amount == Token.bast_to_juillet(1789.0)
      end
    end
  end

  describe "transaction edge cases" do
    test "handles zero amounts appropriately" do
      # Test behavior with zero amount (should this be allowed?)
      tx = Transaction.new([
        from: "f789zero_test",
        to: "f789zero_receiver",
        amount: 0,
        nonce: 1
      ])

      assert tx.amount == 0
      assert tx.fee > 0
    end

    test "validates same from/to addresses" do
      # Self-transaction (might be allowed for certain operations)
      address = "f789self_transaction"

      tx = Transaction.new([
        from: address,
        to: address,
        amount: Token.bast_to_juillet(1.0),
        nonce: 1
      ])

      assert tx.from == tx.to
      assert tx.amount > 0
    end

    test "handles large transaction amounts" do
      # Test very large amounts
      large_amount = Token.bast_to_juillet(1_000_000.0)

      tx = Transaction.new([
        from: "f789large_sender",
        to: "f789large_receiver",
        amount: large_amount,
        nonce: 1
      ])

      assert tx.amount == large_amount
      assert tx.amount > tx.fee
      assert is_integer(tx.amount)
    end
  end

  describe "transaction metadata" do
    test "includes proper timestamp" do
      tx = Transaction.new([
        from: "f789timestamp_test",
        to: "f789timestamp_receiver",
        amount: Token.bast_to_juillet(1.0),
        nonce: 1
      ])

      assert is_integer(tx.timestamp)
      assert tx.timestamp > 0
      # Timestamp should be recent (within last year)
      current_time = System.system_time(:second)
      assert tx.timestamp <= current_time
      assert tx.timestamp > (current_time - 365 * 24 * 60 * 60)
    end

    test "supports transaction data/memo fields" do
      memo = "Payment for revolutionary services"

      tx = Transaction.new([
        from: "f789memo_sender",
        to: "f789memo_receiver",
        amount: Token.bast_to_juillet(1.0),
        nonce: 1,
        data: memo
      ])

      if Map.has_key?(tx, :data) do
        assert tx.data == memo
        assert is_binary(tx.data)
      end
    end
  end
end
