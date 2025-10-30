defmodule Bastille.Features.Block.CreationTest do

  use ExUnit.Case, async: true

  alias Bastille.Features.Block.Block
  alias Bastille.Features.Tokenomics.Token
  alias Bastille.TestHelper

  @moduletag :unit

  describe "block creation" do
    test "creates a valid genesis block" do
      block = Block.new([
        index: 0,
        previous_hash: <<0::256>>,
        transactions: [],
        difficulty: 1,
        timestamp: 1752422400  # Bastille Day 2025
      ])

      assert Block.height(block) == 0
      assert block.header.previous_hash == <<0::256>>
      assert block.header.difficulty == 1
      assert block.header.timestamp == 1752422400
      assert is_list(block.transactions)
      assert Enum.empty?(block.transactions)
      refute is_nil(block.header.merkle_root)
    end

    test "creates block with transactions" do
      # Create a test transaction
      tx = TestHelper.create_test_transaction([
        from: "f789sender123456789",
        to: "f789receiver123456789",
        amount: Token.bast_to_juillet(10.0),
        fee: Token.bast_to_juillet(0.001)
      ])

      block = Block.new([
        index: 1,
        previous_hash: <<1::256>>,
        transactions: [tx],
        difficulty: 4
      ])

      assert Block.height(block) == 1
      assert length(block.transactions) == 1
      assert hd(block.transactions) == tx
      assert block.header.merkle_root != <<0::256>>
    end

    test "creates block with multiple transactions" do
      transactions = Enum.map(1..5, fn i ->
        TestHelper.create_test_transaction([
          from: "f789sender#{i}",
          to: "f789receiver#{i}",
          amount: Token.bast_to_juillet(i * 1.0),
          fee: Token.bast_to_juillet(0.001),
          nonce: i
        ])
      end)

      block = Block.new([
        index: 2,
        previous_hash: <<2::256>>,
        transactions: transactions,
        difficulty: 8
      ])

      assert Block.height(block) == 2
      assert length(block.transactions) == 5
      assert block.header.merkle_root != <<0::256>>
    end
  end

  describe "block validation" do
    test "validates block structure" do
      block = Block.new([
        index: 1,
        previous_hash: <<1::256>>,
        transactions: [],
        difficulty: 4
      ])

      # Should have valid structure even without hash
      assert Block.valid_structure_without_hash?(block)
    end

    test "handles invalid index gracefully" do
      # Try with invalid index but don't expect exception
      block = Block.new([
        index: -1,
        previous_hash: <<1::256>>,
        transactions: [],
        difficulty: 4
      ])

      # Check if block was created with corrected values or invalid structure
      assert is_struct(block, Block)
    end

    test "handles invalid difficulty gracefully" do
      # Try with invalid difficulty but don't expect exception
      block = Block.new([
        index: 1,
        previous_hash: <<1::256>>,
        transactions: [],
        difficulty: 0
      ])

      # Check if block was created
      assert is_struct(block, Block)
    end

    test "validates timestamp is reasonable" do
      block = Block.new([
        index: 1,
        previous_hash: <<1::256>>,
        transactions: [],
        difficulty: 4,
        timestamp: System.system_time(:second)
      ])

      # Should accept current timestamp
      assert Block.valid_structure_without_hash?(block)
    end
  end

  describe "block hashing" do
    test "calculates consistent hash" do
      block = Block.new([
        index: 1,
        previous_hash: <<1::256>>,
        transactions: [],
        difficulty: 4,
        nonce: 12345
      ])

      updated_block1 = Block.calculate_hash(block)
      updated_block2 = Block.calculate_hash(block)

      assert updated_block1.hash == updated_block2.hash
      assert is_binary(updated_block1.hash)
      assert byte_size(updated_block1.hash) == 32
    end

    test "different blocks have different hashes" do
      block1 = Block.new([
        index: 1,
        previous_hash: <<1::256>>,
        transactions: [],
        difficulty: 4
      ])

      block2 = Block.new([
        index: 2,
        previous_hash: <<1::256>>,
        transactions: [],
        difficulty: 4
      ])

      updated_block1 = Block.calculate_hash(block1)
      updated_block2 = Block.calculate_hash(block2)

      assert updated_block1.hash != updated_block2.hash
    end

    test "nonce changes affect hash" do
      base_block = Block.new([
        index: 1,
        previous_hash: <<1::256>>,
        transactions: [],
        difficulty: 4
      ])

      block_nonce1 = %{base_block | header: %{base_block.header | nonce: 1}}
      block_nonce2 = %{base_block | header: %{base_block.header | nonce: 2}}

      updated_block1 = Block.calculate_hash(block_nonce1)
      updated_block2 = Block.calculate_hash(block_nonce2)

      assert updated_block1.hash != updated_block2.hash
    end
  end

  describe "merkle tree" do
    test "empty transaction list has known merkle root" do
      block = Block.new([
        index: 0,
        previous_hash: <<0::256>>,
        transactions: [],
        difficulty: 1
      ])

      # Empty merkle root should be consistent
      assert is_binary(block.header.merkle_root)
      assert byte_size(block.header.merkle_root) == 32
    end

    test "single transaction merkle root" do
      tx = TestHelper.create_test_transaction([
        amount: Token.bast_to_juillet(5.0)
      ])

      block = Block.new([
        index: 1,
        previous_hash: <<1::256>>,
        transactions: [tx],
        difficulty: 4
      ])

      assert is_binary(block.header.merkle_root)
      assert block.header.merkle_root != <<0::256>>
    end

    test "multiple transactions produce valid merkle root" do
      transactions = Enum.map(1..3, fn i ->
        TestHelper.create_test_transaction([
          amount: Token.bast_to_juillet(i * 1.0),
          nonce: i
        ])
      end)

      block = Block.new([
        index: 1,
        previous_hash: <<1::256>>,
        transactions: transactions,
        difficulty: 4
      ])

      assert is_binary(block.header.merkle_root)
      assert block.header.merkle_root != <<0::256>>

      # Different transaction order should produce different merkle root
      shuffled_transactions = Enum.reverse(transactions)
      block_shuffled = Block.new([
        index: 1,
        previous_hash: <<1::256>>,
        transactions: shuffled_transactions,
        difficulty: 4
      ])

      assert block.header.merkle_root != block_shuffled.header.merkle_root
    end
  end

  describe "block properties" do
    test "validates block structure" do
      block = Block.new([
        index: 1,
        previous_hash: <<1::256>>,
        transactions: [],
        difficulty: 4
      ])

      assert Block.valid_structure_without_hash?(block)
      assert is_integer(block.header.timestamp)
      assert is_integer(block.header.nonce)
      assert is_integer(block.header.difficulty)
    end

    test "validates block height accessor" do
      block = Block.new([
        index: 42,
        previous_hash: <<42::256>>,
        transactions: [],
        difficulty: 4
      ])

      assert Block.height(block) == 42
    end
  end
end
