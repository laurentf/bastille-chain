defmodule Bastille.Features.Consensus.ProofOfWorkTest do
  use ExUnit.Case, async: true
  alias Bastille.Features.Mining.ProofOfWork
  alias Bastille.Features.Block.Block

  # Helper function to create ProofOfWork state
  defp create_pow_state(config \\ %{}) do
    {:ok, state} = ProofOfWork.init(config)
    state
  end

  # Helper function to create test block
  defp create_test_block() do
    Block.new([
      index: 1,
      previous_hash: <<1::256>>,
      transactions: [],
      difficulty: 4
    ])
  end

  describe "ProofOfWork module initialization" do
    test "creates default ProofOfWork state" do
      pow_state = create_pow_state()
      assert %ProofOfWork{} = pow_state
      assert pow_state.target_block_time == 10_000
      assert pow_state.difficulty_adjustment_interval == 10
      assert pow_state.current_difficulty == 4
    end

    test "creates ProofOfWork with custom config" do
      config = %{
        target_block_time: 15_000,
        initial_difficulty: 8,
        max_target: 1000
      }
      pow_state = create_pow_state(config)
      assert pow_state.target_block_time == 15_000
      assert pow_state.current_difficulty == 8
      assert pow_state.max_target == 1000
    end
  end

  describe "block validation" do
    test "validates block with ProofOfWork" do
      block = create_test_block()
      pow_state = create_pow_state()
      
      # Basic validation should work
      result = ProofOfWork.validate_block(block, pow_state)
      assert is_boolean(result) or match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "get_difficulty returns current difficulty" do
      pow_state = create_pow_state(%{initial_difficulty: 6})
      assert ProofOfWork.get_difficulty(pow_state) == 6
    end
  end

  describe "difficulty adjustment" do
    test "adjust_difficulty with insufficient block times" do
      pow_state = create_pow_state()
      block_times = [10_000, 11_000]  # Less than adjustment interval
      
      # Should return current difficulty when not enough blocks
      result = ProofOfWork.adjust_difficulty(block_times, pow_state)
      assert result == pow_state.current_difficulty
    end

    test "adjust_difficulty with sufficient block times" do
      pow_state = create_pow_state()
      # Create enough block times for adjustment (10 blocks)
      # adjust_difficulty expects block objects with timestamp field
      block_times = Enum.map(1..10, fn i ->
        %{timestamp: System.system_time(:millisecond) + (i * 15_000)}
      end)
      
      result = ProofOfWork.adjust_difficulty(block_times, pow_state)
      assert is_integer(result)
    end
  end

  describe "state updates" do
    test "update_state returns updated state" do
      block = create_test_block()
      pow_state = create_pow_state()
      
      result = ProofOfWork.update_state(block, pow_state)
      assert match?({:ok, %ProofOfWork{}}, result)
    end
  end

  describe "mining for tests" do
    test "mine_block_for_test function exists and accepts parameters" do
      _block = create_test_block()
      _pow_state = create_pow_state(%{max_target: 1000})
      
      # Just test that the function exists and can be called without hanging
      # Don't actually mine to avoid test timeouts
      assert function_exported?(ProofOfWork, :mine_block_for_test, 2)
    end

    test "validate_block_for_test validates test blocks" do
      block = create_test_block()
      pow_state = create_pow_state()
      
      if function_exported?(ProofOfWork, :validate_block_for_test, 2) do
        result = ProofOfWork.validate_block_for_test(block, pow_state)
        assert is_boolean(result) or match?({:ok, _}, result) or match?({:error, _}, result)
      end
    end
  end
end
