defmodule Bastille.Features.Transaction.EmbeddedPublicKeysTest do
  @moduledoc """
  A signed transaction embeds the sender's three PQ public keys so any node can
  verify it without having seen the sender before. These tests pin the property
  end to end: the keys survive the JSON (RPC) and protobuf (P2P) boundaries, a
  receiving node can verify the signature with no prior State, and the embedded
  keys are trusted only when they hash to `from` (otherwise they are a forgery
  vector).
  """
  use ExUnit.Case, async: false

  alias Bastille.Features.Transaction.{Transaction, TransactionConverter}
  alias Bastille.Features.Block.BlockConverter
  alias Bastille.Features.P2P.Messaging.{Codec, Messages}
  alias Bastille.Shared.Crypto

  @moduletag :unit

  # A signed tx whose `from` derives from `kp`, with the matching public keys
  # embedded — exactly what RPC sign_transaction now produces.
  defp signed_tx(kp \\ Crypto.generate_pq_keypair()) do
    from = Crypto.generate_bastille_address(kp)
    to = Crypto.generate_bastille_address(Crypto.generate_pq_keypair())

    signed =
      [from: from, to: to, amount: 1000, nonce: 0]
      |> Transaction.new()
      |> Transaction.sign(kp)

    pubs = pubs_of(kp)
    {%{signed | public_keys: pubs}, pubs}
  end

  defp pubs_of(kp) do
    %{dilithium: kp.dilithium.public, falcon: kp.falcon.public, sphincs: kp.sphincs.public}
  end

  describe "verification with embedded keys" do
    test "a node verifies the signature with no public keys stored for the sender" do
      {tx, _pubs} = signed_tx()
      # resolve_public_keys takes the embedded branch and never touches State,
      # so this holds even though the sender was never seen by this node.
      assert Transaction.verify_signature(tx)
    end

    test "embedded keys that do not hash to `from` are rejected (forgery vector)" do
      victim = Crypto.generate_pq_keypair()
      from = Crypto.generate_bastille_address(victim)

      attacker = Crypto.generate_pq_keypair()

      # Attacker signs with their own keys but claims the victim's address and
      # attaches their own (validly self-signed) public keys.
      forged =
        [from: from, to: from, amount: 1000, nonce: 0]
        |> Transaction.new()
        |> Transaction.sign(attacker)

      forged = %{forged | public_keys: pubs_of(attacker)}

      refute Transaction.verify_signature(forged)
    end
  end

  describe "JSON (RPC) boundary" do
    test "to_json_map/from_json_map preserves the embedded keys and they still verify" do
      {tx, pubs} = signed_tx()

      assert {:ok, parsed} = tx |> Transaction.to_json_map() |> Transaction.from_json_map()
      assert parsed.public_keys == pubs
      assert Transaction.verify_signature(parsed)
    end

    test "an unsigned transaction has no public_keys key on the wire" do
      tx = Transaction.new(from: addr(), to: addr(), amount: 1, nonce: 0)
      refute Map.has_key?(Transaction.to_json_map(tx), "public_keys")
    end
  end

  describe "P2P (protobuf) boundary" do
    test "embedded keys survive tx_message -> encode -> decode -> converter and verify" do
      {tx, pubs} = signed_tx()

      {:ok, frame} = Codec.encode(:tx, Messages.tx_message(tx)[:tx])
      {:ok, {:tx, decoded_map}} = Codec.decode(IO.iodata_to_binary(frame))
      assert {:ok, converted} = TransactionConverter.from_p2p_data(decoded_map)

      assert converted.public_keys == pubs
      assert Transaction.verify_signature(converted)
    end

    test "a block carrying a signed user tx converts and the tx verifies" do
      {tx, pubs} = signed_tx()

      block = %Bastille.Features.Block.Block{
        hash: :crypto.strong_rand_bytes(32),
        header: %{
          index: 1,
          previous_hash: :crypto.strong_rand_bytes(32),
          timestamp: 1_700_000_000,
          merkle_root: :crypto.strong_rand_bytes(32),
          nonce: 0,
          difficulty: 1,
          consensus_data: %{}
        },
        transactions: [tx]
      }

      {:ok, frame} = Codec.encode(:block, Messages.block_message(block)[:block])
      {:ok, {:block, decoded_map}} = Codec.decode(IO.iodata_to_binary(frame))
      assert {:ok, converted_block} = BlockConverter.from_p2p_data(decoded_map)

      [converted_tx] = converted_block.transactions
      assert converted_tx.signature_type == :post_quantum_2_of_3
      assert converted_tx.public_keys == pubs
      assert Transaction.verify_signature(converted_tx)
    end
  end

  defp addr do
    prefix = Application.get_env(:bastille, :address_prefix, "f789")
    prefix <> String.duplicate("a", 40)
  end
end
