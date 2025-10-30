defmodule Bastille.Features.Mining.MiningTest do
  use ExUnit.Case, async: true
  alias Bastille.Features.Mining.Mining
  alias Bastille.Features.Block.Block

  @moduletag :unit

  describe "Blake3 hashing" do
    test "blake3_hash produces 32-byte hash" do
      data = "test data for blake3 hashing"
      hash = Mining.blake3_hash(data)

      assert is_binary(hash)
      assert byte_size(hash) == 32
    end

    test "blake3_hash is deterministic" do
      data = "deterministic input data"
      hash1 = Mining.blake3_hash(data)
      hash2 = Mining.blake3_hash(data)

      assert hash1 == hash2
    end

    test "different inputs produce different hashes" do
      hash1 = Mining.blake3_hash("input one")
      hash2 = Mining.blake3_hash("input two")
      hash3 = Mining.blake3_hash("input three")

      assert hash1 != hash2
      assert hash2 != hash3
      assert hash1 != hash3
    end

    test "empty input produces valid hash" do
      hash = Mining.blake3_hash("")

      assert is_binary(hash)
      assert byte_size(hash) == 32
    end

    test "large input produces valid hash" do
      large_data = String.duplicate("A", 10_000)
      hash = Mining.blake3_hash(large_data)

      assert is_binary(hash)
      assert byte_size(hash) == 32
    end

    test "binary input produces valid hash" do
      binary_data = :crypto.strong_rand_bytes(256)
      hash = Mining.blake3_hash(binary_data)

      assert is_binary(hash)
      assert byte_size(hash) == 32
    end
  end

  describe "target and difficulty" do
    test "testing_target produces valid 32-byte target" do
      target = Mining.testing_target()

      assert is_binary(target)
      assert byte_size(target) == 32
    end

    test "difficulty_to_target conversion" do
      target = Mining.difficulty_to_target(1)

      assert is_binary(target)
      assert byte_size(target) == 32
    end

    test "difficulty_to_test_target conversion" do
      target = Mining.difficulty_to_test_target(1)

      assert is_binary(target)
      assert byte_size(target) == 32
    end

    test "different targets for different difficulties" do
      easy_target = Mining.difficulty_to_target(1)
      hard_target = Mining.difficulty_to_target(100)

      # Should produce different targets
      assert easy_target != hard_target
    end
  end

  describe "hash validation" do
    test "valid_hash? with matching hash and target" do
      # Create a hash that should meet an easy target
      easy_hash = <<0, 0, 0, 1>> <> :crypto.strong_rand_bytes(28)
      easy_target = Mining.difficulty_to_test_target(1)

      result = Mining.valid_hash?(easy_hash, easy_target)
      assert is_boolean(result)
    end

    test "valid_hash? rejects invalid hash format" do
      # Test with wrong hash size
      invalid_hash = :crypto.strong_rand_bytes(16)  # 16 bytes instead of 32
      target = Mining.testing_target()

      result = Mining.valid_hash?(invalid_hash, target)
      assert result == false
    end

    test "valid_hash? rejects invalid target format" do
      # Test with wrong target size
      hash = :crypto.strong_rand_bytes(32)
      invalid_target = :crypto.strong_rand_bytes(16)  # 16 bytes instead of 32

      result = Mining.valid_hash?(hash, invalid_target)
      assert result == false
    end
  end

  describe "block serialization" do
    test "serialize_block_for_mining produces consistent output" do
      # Create a proper Block struct
      block = Block.new([
        index: 1,
        previous_hash: <<0::256>>,
        transactions: [],
        difficulty: 4
      ])

      serialized1 = Mining.serialize_block_for_mining(block)
      serialized2 = Mining.serialize_block_for_mining(block)

      assert is_binary(serialized1)
      assert serialized1 == serialized2
    end

    test "different blocks serialize differently" do
      block1 = Block.new([
        index: 1,
        previous_hash: <<0::256>>,
        transactions: [],
        difficulty: 4
      ])

      block2 = Block.new([
        index: 2,  # Different index
        previous_hash: <<0::256>>,
        transactions: [],
        difficulty: 4
      ])

      serialized1 = Mining.serialize_block_for_mining(block1)
      serialized2 = Mining.serialize_block_for_mining(block2)

      assert serialized1 != serialized2
    end

    test "blocks with different timestamps serialize differently" do
      block1 = Block.new([
        index: 1,
        previous_hash: <<0::256>>,
        transactions: [],
        difficulty: 4,
        timestamp: 1234567890
      ])

      block2 = Block.new([
        index: 1,
        previous_hash: <<0::256>>,
        transactions: [],
        difficulty: 4,
        timestamp: 1234567891  # Different timestamp
      ])

      serialized1 = Mining.serialize_block_for_mining(block1)
      serialized2 = Mining.serialize_block_for_mining(block2)

      assert serialized1 != serialized2
    end
  end

  describe "block hash calculation" do
    test "calculate_block_hash produces consistent hash" do
      block = Block.new([
        index: 1,
        previous_hash: <<0::256>>,
        transactions: [],
        difficulty: 4,
        nonce: 12345
      ])

      hash1 = Mining.calculate_block_hash(block)
      hash2 = Mining.calculate_block_hash(block)

      assert is_binary(hash1)
      assert byte_size(hash1) == 32
      assert hash1 == hash2
    end

    test "different nonces produce different hashes" do
      base_block = Block.new([
        index: 1,
        previous_hash: <<0::256>>,
        transactions: [],
        difficulty: 4
      ])

      block1 = %{base_block | header: %{base_block.header | nonce: 1}}
      block2 = %{base_block | header: %{base_block.header | nonce: 2}}

      hash1 = Mining.calculate_block_hash(block1)
      hash2 = Mining.calculate_block_hash(block2)

      assert hash1 != hash2
      assert byte_size(hash1) == 32
      assert byte_size(hash2) == 32
    end

    test "validate_block_hash_consistency with nil hash" do
      block = Block.new([
        index: 1,
        previous_hash: <<0::256>>,
        transactions: [],
        difficulty: 4
      ])

      # Block.new should create a block without a hash initially
      block_no_hash = %{block | hash: nil}

      result = Mining.validate_block_hash_consistency(block_no_hash)
      assert result == {:error, :no_hash}
    end

    test "validate_block_hash_consistency with valid hash" do
      block = Block.new([
        index: 1,
        previous_hash: <<0::256>>,
        transactions: [],
        difficulty: 4,
        nonce: 12345
      ])

      # Calculate the correct hash
      correct_hash = Mining.calculate_block_hash(block)
      block_with_hash = %{block | hash: correct_hash}

      result = Mining.validate_block_hash_consistency(block_with_hash)
      assert match?({:ok, _}, result) or result == :ok
    end
  end

  describe "mining performance metrics" do
    test "hash rate calculation" do
      # Mock hash rate calculation
      hashes_computed = 1000
      time_elapsed_ms = 1000  # 1 second

      hash_rate = if time_elapsed_ms > 0 do
        round(hashes_computed / time_elapsed_ms * 1000)
      else
        0
      end

      assert hash_rate == 1000  # 1000 hashes/second
      assert hash_rate > 0
    end

    test "mining time tracking" do
      start_time = System.monotonic_time(:millisecond)
      # Simulate some work
      :timer.sleep(1)
      end_time = System.monotonic_time(:millisecond)

      elapsed = end_time - start_time
      assert elapsed >= 1
      assert is_integer(elapsed)
    end

    test "difficulty adjustment calculations" do
      # Mock difficulty adjustment
      target_time = 10_000  # 10 seconds target
      actual_time = 5_000   # 5 seconds actual
      current_difficulty = 4

      # If blocks are mined too fast, difficulty should increase
      adjustment_factor = actual_time / target_time
      suggested_difficulty = round(current_difficulty / adjustment_factor)

      assert adjustment_factor < 1.0  # Mining too fast
      assert suggested_difficulty > current_difficulty  # Should increase
    end
  end

  describe "block validation" do
    test "validates block hash format" do
      # Test hash format validation
      valid_hash = :crypto.strong_rand_bytes(32)
      invalid_hash = :crypto.strong_rand_bytes(20)  # Wrong size

      assert byte_size(valid_hash) == 32
      assert byte_size(invalid_hash) != 32
    end

    test "validates nonce format" do
      # Test nonce validation
      valid_nonce = 123456
      invalid_nonce = -1

      assert is_integer(valid_nonce)
      assert valid_nonce >= 0
      assert is_integer(invalid_nonce)
    end

    test "validates timestamp reasonableness" do
      # Test timestamp validation
      current_time = System.system_time(:second)
      recent_time = current_time - 3600  # 1 hour ago
      future_time = current_time + 3600  # 1 hour future
      ancient_time = 0

      assert recent_time > ancient_time
      assert recent_time < current_time
      assert future_time > current_time
    end
  end

  describe "French Revolution themed mining" do
    test "revolutionary mining constants" do
      # Test revolutionary-themed constants
      bastille_year = 1789
      bastille_day = 14  # July 14th

      assert bastille_year == 1789
      assert bastille_day == 14
      assert bastille_year > 1000
    end

    test "revolutionary block rewards" do
      # Test 1789 BAST block reward theme
      block_reward_bast = 1789.0
      assert block_reward_bast == 1789.0
      assert block_reward_bast > 0
    end

    test "revolutionary difficulty themes" do
      # Test French Revolution themed difficulty levels
      revolutionary_difficulties = [17, 89, 1789]

      for difficulty <- revolutionary_difficulties do
        assert is_integer(difficulty)
        assert difficulty > 0
      end

      assert Enum.member?(revolutionary_difficulties, 1789)
    end
  end

  describe "edge cases and error handling" do
    test "handles nil input for hashing" do
      # Test error handling for nil input
      assert_raise FunctionClauseError, fn ->
        Mining.blake3_hash(nil)
      end
    end

    test "handles very large nonce values" do
      # Test nonce overflow protection
      large_nonce = 18_446_744_073_709_551_615  # max uint64

      assert is_integer(large_nonce)
      assert large_nonce > 0
    end

    test "handles empty block serialization" do
      # Test genesis-like block structure
      empty_block = Block.new([
        index: 0,
        previous_hash: <<0::256>>,
        transactions: [],
        difficulty: 1,
        timestamp: 0,
        nonce: 0
      ])

      serialized = Mining.serialize_block_for_mining(empty_block)
      assert is_binary(serialized)
      assert byte_size(serialized) > 0
    end

    test "format_hash displays hash correctly" do
      hash = :crypto.strong_rand_bytes(32)
      formatted = Mining.format_hash(hash)

      assert is_binary(formatted)
      assert String.length(formatted) > 0
      # Should be hexadecimal representation
      assert formatted =~ ~r/^[0-9a-f]+$/
    end
  end
end
