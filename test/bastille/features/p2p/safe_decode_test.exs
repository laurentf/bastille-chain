defmodule Bastille.Features.P2P.SafeDecodeTest do
  @moduledoc """
  P2P deserialization must use `:erlang.binary_to_term/2` with `[:safe]`: peer
  bytes are untrusted, and a raw decode lets a hostile peer mint arbitrary atoms
  → atom-table exhaustion (a remote DoS, the table is never GC'd). These tests
  pin both halves: legit payloads still decode, hostile ones are rejected without
  creating the atom.
  """

  use ExUnit.Case, async: true

  alias Bastille.Features.Block.BlockConverter
  alias Bastille.Features.Transaction.Transaction
  alias Bastille.Features.P2P.Messaging.{Codec, Messages}

  @moduletag :unit

  # ETF for an atom, built from raw bytes so the atom is NOT created in this VM:
  # <<131 (version), 119 (SMALL_ATOM_UTF8_EXT), len::8, name>>.
  defp etf_atom(name), do: <<131, 119, byte_size(name)::8, name::binary>>

  defp valid_block_data(consensus_data) do
    %{
      "hash" => <<0::256>>,
      "header" => %{
        "index" => 1,
        "previous_hash" => String.duplicate("0", 64),
        "merkle_root" => String.duplicate("0", 64),
        "timestamp" => 1_700_000_000,
        "nonce" => 0,
        "difficulty" => 1,
        "consensus_data" => consensus_data
      },
      "transactions" => []
    }
  end

  describe "legit payloads still decode (no regression from :safe)" do
    test "a transaction's map signature round-trips through the codec" do
      sig = %{dilithium: <<1, 2, 3>>, falcon: <<4, 5>>, sphincs: <<6>>}

      tx = %Transaction{
        from: "f789" <> String.duplicate("a", 40),
        to: "f789" <> String.duplicate("b", 40),
        amount: 1000,
        fee: 10,
        nonce: 1,
        timestamp: 1_700_000_000,
        data: "",
        signature: sig,
        signature_type: :regular,
        hash: :crypto.strong_rand_bytes(32)
      }

      {:ok, frame} = Codec.encode(:tx, Messages.tx_message(tx)[:tx])
      {:ok, {:tx, payload}} = Codec.decode(IO.iodata_to_binary(frame))

      assert payload["signature"] == sig
    end

    test "block consensus_data with known atoms decodes" do
      consensus = :erlang.term_to_binary(%{genesis: true, network: "bastille"})

      assert {:ok, block} = BlockConverter.from_p2p_data(valid_block_data(consensus))
      assert block.header.consensus_data == %{genesis: true, network: "bastille"}
    end
  end

  describe "hostile payloads are rejected without minting atoms" do
    test "a novel atom in consensus_data is dropped, not created" do
      name = "evilatom_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
      # Sanity: the atom does not exist yet.
      assert_raise ArgumentError, fn -> String.to_existing_atom(name) end

      assert {:ok, block} = BlockConverter.from_p2p_data(valid_block_data(etf_atom(name)))

      # :safe rejected it → fell back to the empty map, and crucially the atom
      # was never added to the table.
      assert block.header.consensus_data == %{}
      assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
    end
  end
end
