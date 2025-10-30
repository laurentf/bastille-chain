defmodule Bastille.Features.Tokenomics.CoinbaseMaturityTest do
  use ExUnit.Case, async: false  # Not async because it uses GenServer
  doctest Bastille.Features.Tokenomics.CoinbaseMaturity

  alias Bastille.Features.Tokenomics.CoinbaseMaturity
  alias Bastille.Features.Tokenomics.CoinbaseMaturity.CoinbaseReward
  alias Bastille.Infrastructure.Storage.CubDB.State

  setup do
    # Start required services for testing
    unless Process.whereis(State) do
      {:ok, _} = State.start_link([])
    end
    
    unless Process.whereis(CoinbaseMaturity) do
      {:ok, _} = CoinbaseMaturity.start_link([])
    end
    
    # Give services time to start
    :timer.sleep(100)
    
    # Clear any leftover state from previous tests
    CoinbaseMaturity.clear_all_immature()
    
    # Test addresses and unique identifiers - use unique values per test to avoid conflicts
    test_id = :rand.uniform(1000000)
    miner_address = "f789test#{test_id}miner#{System.system_time(:nanosecond)}"
    other_address = "f789test#{test_id}other#{System.system_time(:nanosecond)}"
    
    {:ok, miner_address: miner_address, other_address: other_address, test_id: test_id}
  end

  describe "add_coinbase_reward/4" do
    test "adds immature coinbase reward correctly", %{miner_address: miner_address} do
      block_hash = <<1::256>>
      amount = 178900000000  # 1789 BAST
      block_height = 10

      # First, add the balance to State storage (simulating what Chain module does)
      State.update_balance(miner_address, amount)

      # Then register it as immature
      assert :ok = CoinbaseMaturity.add_coinbase_reward(block_hash, amount, miner_address, block_height)

      # Check that the balance breakdown shows the reward
      breakdown = CoinbaseMaturity.get_balance_breakdown(miner_address)
      assert breakdown.total == amount
      assert breakdown.immature == amount
      assert breakdown.mature == 0  # Should be 0 since it's immature (total - immature)
    end

    test "adds multiple coinbase rewards for same miner", %{miner_address: miner_address} do
      block_hash1 = <<1::256>>
      block_hash2 = <<2::256>>
      amount = 178900000000
      
      # First, add balances to State storage (simulating what Chain module does)
      State.update_balance(miner_address, amount)
      CoinbaseMaturity.add_coinbase_reward(block_hash1, amount, miner_address, 10)
      
      State.update_balance(miner_address, amount * 2)  # Update to total of both
      CoinbaseMaturity.add_coinbase_reward(block_hash2, amount, miner_address, 11)

      breakdown = CoinbaseMaturity.get_balance_breakdown(miner_address)
      assert breakdown.total == amount * 2
      assert breakdown.immature == amount * 2
      assert breakdown.mature == 0
    end
  end

  describe "get_balance_breakdown/1" do
    test "returns correct breakdown for address with no rewards", %{other_address: other_address} do
      breakdown = CoinbaseMaturity.get_balance_breakdown(other_address)
      assert breakdown.total == 0
      assert breakdown.immature == 0
      assert breakdown.mature == 0
    end

    test "handles mixed mature and immature balances", %{miner_address: miner_address} do
      # Add some regular balance to State storage (simulating mature balance)
      mature_balance = 500000000000  # 500 BAST
      State.update_balance(miner_address, mature_balance)
      
      # Add immature coinbase (update State total to include both)
      immature_amount = 178900000000  # 1789 BAST
      State.update_balance(miner_address, mature_balance + immature_amount)
      CoinbaseMaturity.add_coinbase_reward(<<1::256>>, immature_amount, miner_address, 10)

      breakdown = CoinbaseMaturity.get_balance_breakdown(miner_address)
      assert breakdown.total == mature_balance + immature_amount
      assert breakdown.immature == immature_amount
      assert breakdown.mature == mature_balance  # Should be total - immature
    end
  end

  describe "get_immature_coinbases/1" do
    test "returns empty list for address with no rewards", %{other_address: other_address} do
      immature_coinbases = CoinbaseMaturity.get_immature_coinbases(other_address)
      assert immature_coinbases == []
    end

    test "returns immature coinbases sorted by block height", %{miner_address: miner_address} do
      block_hash1 = <<1::256>>
      block_hash2 = <<2::256>>
      block_hash3 = <<3::256>>
      amount = 178900000000
      
      CoinbaseMaturity.add_coinbase_reward(block_hash1, amount, miner_address, 10)
      CoinbaseMaturity.add_coinbase_reward(block_hash3, amount, miner_address, 12)
      CoinbaseMaturity.add_coinbase_reward(block_hash2, amount, miner_address, 11)

      immature_coinbases = CoinbaseMaturity.get_immature_coinbases(miner_address)
      assert length(immature_coinbases) == 3
      
      # Should be sorted by block_height descending
      assert Enum.at(immature_coinbases, 0).block_height == 12
      assert Enum.at(immature_coinbases, 1).block_height == 11  
      assert Enum.at(immature_coinbases, 2).block_height == 10
    end
  end

  describe "process_maturity/1" do
    test "matures coinbases when enough blocks have passed", %{miner_address: miner_address, test_id: test_id} do
      # Add coinbase at height 10 (simulate Chain module behavior)
      block_hash = <<test_id::256>>  # Use unique hash per test
      amount = 178900000000
      block_height = 10
      
      State.update_balance(miner_address, amount)
      CoinbaseMaturity.add_coinbase_reward(block_hash, amount, miner_address, block_height)
      
      # Initial state - should be immature
      breakdown = CoinbaseMaturity.get_balance_breakdown(miner_address)
      assert breakdown.immature == amount
      assert breakdown.mature == 0

      # Process maturity - not enough blocks yet (need 5 blocks in test)
      {:ok, result} = CoinbaseMaturity.process_maturity(14)  # Only 4 blocks passed
      assert result[:matured] == 0
      assert result[:orphaned] == 0

      # Process maturity - enough blocks passed
      {:ok, result} = CoinbaseMaturity.process_maturity(15)  # 5 blocks passed (10 + 5 = 15)
      assert result[:matured] == 1
      assert result[:orphaned] == 0

      # Check that balance breakdown reflects maturation
      breakdown = CoinbaseMaturity.get_balance_breakdown(miner_address)
      assert breakdown.immature == 0  # Should be 0 now
      assert breakdown.mature == amount  # Should be the full amount
    end

    test "handles multiple rewards with different maturity heights", %{miner_address: miner_address, test_id: test_id} do
      amount = 178900000000
      
      # Add rewards at different heights (simulate Chain adding balances) - use unique hashes
      State.update_balance(miner_address, amount)
      CoinbaseMaturity.add_coinbase_reward(<<test_id + 1000::256>>, amount, miner_address, 10)  # Matures at 15
      
      State.update_balance(miner_address, amount * 2)
      CoinbaseMaturity.add_coinbase_reward(<<test_id + 2000::256>>, amount, miner_address, 12)  # Matures at 17
      
      State.update_balance(miner_address, amount * 3)
      CoinbaseMaturity.add_coinbase_reward(<<test_id + 3000::256>>, amount, miner_address, 14)  # Matures at 19

      # Process at height 16 - only first reward should mature
      {:ok, result} = CoinbaseMaturity.process_maturity(16)
      assert result[:matured] == 1
      
      breakdown = CoinbaseMaturity.get_balance_breakdown(miner_address)
      assert breakdown.immature == amount * 2  # 2 still immature
      assert breakdown.mature == amount       # 1 matured

      # Process at height 18 - second reward should mature
      {:ok, result} = CoinbaseMaturity.process_maturity(18)
      assert result[:matured] == 1
      
      breakdown = CoinbaseMaturity.get_balance_breakdown(miner_address)
      assert breakdown.immature == amount     # 1 still immature
      assert breakdown.mature == amount * 2   # 2 matured

      # Process at height 20 - third reward should mature
      {:ok, result} = CoinbaseMaturity.process_maturity(20)
      assert result[:matured] == 1
      
      breakdown = CoinbaseMaturity.get_balance_breakdown(miner_address)
      assert breakdown.immature == 0          # None immature
      assert breakdown.mature == amount * 3   # All matured
    end
  end

  describe "mark_block_orphaned/1" do
    test "removes orphaned block reward from balance", %{miner_address: miner_address} do
      block_hash = <<1::256>>
      amount = 178900000000
      
      # Add balance to State storage and track as immature
      State.update_balance(miner_address, amount)
      CoinbaseMaturity.add_coinbase_reward(block_hash, amount, miner_address, 10)
      
      # Initial balance should include the reward
      breakdown = CoinbaseMaturity.get_balance_breakdown(miner_address)
      assert breakdown.total == amount
      
      # Mark block as orphaned
      assert :ok = CoinbaseMaturity.mark_block_orphaned(block_hash)
      
      # Balance should be reduced
      breakdown = CoinbaseMaturity.get_balance_breakdown(miner_address)
      assert breakdown.total == 0
      assert breakdown.immature == 0
      assert breakdown.mature == 0
      
      # Immature coinbases should be empty
      immature_coinbases = CoinbaseMaturity.get_immature_coinbases(miner_address)
      assert immature_coinbases == []
    end

    test "handles orphaning non-existent block gracefully" do
      non_existent_hash = <<999::256>>
      assert :ok = CoinbaseMaturity.mark_block_orphaned(non_existent_hash)
    end

    test "only removes the specific orphaned reward", %{miner_address: miner_address} do
      block_hash1 = <<1::256>>
      block_hash2 = <<2::256>>
      amount = 178900000000
      
      # Add balances and track as immature
      State.update_balance(miner_address, amount)
      CoinbaseMaturity.add_coinbase_reward(block_hash1, amount, miner_address, 10)
      
      State.update_balance(miner_address, amount * 2)
      CoinbaseMaturity.add_coinbase_reward(block_hash2, amount, miner_address, 11)
      
      # Should have 2 rewards
      breakdown = CoinbaseMaturity.get_balance_breakdown(miner_address)
      assert breakdown.total == amount * 2
      
      # Orphan only the first block
      CoinbaseMaturity.mark_block_orphaned(block_hash1)
      
      # Should have 1 reward remaining
      breakdown = CoinbaseMaturity.get_balance_breakdown(miner_address)
      assert breakdown.total == amount
      assert breakdown.immature == amount
      
      immature_coinbases = CoinbaseMaturity.get_immature_coinbases(miner_address)
      assert length(immature_coinbases) == 1
      assert Enum.at(immature_coinbases, 0).block_hash == block_hash2
    end
  end

  describe "environment specific maturity blocks" do
    test "uses correct maturity blocks for test environment" do
      # This test runs in test environment, so should use 5 blocks
      block_hash = <<1::256>>
      amount = 178900000000
      
      CoinbaseMaturity.add_coinbase_reward(block_hash, amount, "test_address", 10)
      
      immature_coinbases = CoinbaseMaturity.get_immature_coinbases("test_address")
      reward = Enum.at(immature_coinbases, 0)
      
      # Maturity height should be block_height + 5 (test environment)
      assert reward.maturity_height == 15
    end
  end

  describe "integration with State storage" do
    test "correctly calculates mature balance when State has existing balance", %{miner_address: miner_address} do
      # Start with some existing balance in State
      existing_balance = 1000000000000  # 1000 BAST
      State.update_balance(miner_address, existing_balance)
      
      # Add immature coinbase (update State to include both balances)  
      immature_amount = 178900000000
      State.update_balance(miner_address, existing_balance + immature_amount)
      CoinbaseMaturity.add_coinbase_reward(<<1::256>>, immature_amount, miner_address, 10)
      
      # Total should include both, but mature should only be existing
      breakdown = CoinbaseMaturity.get_balance_breakdown(miner_address)
      assert breakdown.total == existing_balance + immature_amount
      assert breakdown.mature == existing_balance
      assert breakdown.immature == immature_amount
    end

    test "handles zero balance from State correctly", %{other_address: other_address} do
      # Ensure no balance in State (default case)
      breakdown = CoinbaseMaturity.get_balance_breakdown(other_address)
      assert breakdown.total == 0
      assert breakdown.mature == 0
      assert breakdown.immature == 0
    end
  end

  describe "CoinbaseReward struct" do
    test "creates correct CoinbaseReward struct" do
      block_hash = <<1::256>>
      amount = 178900000000
      address = "test_address"
      block_height = 10
      
      State.update_balance(address, amount)
      CoinbaseMaturity.add_coinbase_reward(block_hash, amount, address, block_height)
      
      immature_coinbases = CoinbaseMaturity.get_immature_coinbases(address)
      reward = Enum.at(immature_coinbases, 0)
      
      assert %CoinbaseReward{} = reward
      assert reward.block_hash == block_hash
      assert reward.amount == amount
      assert reward.address == address
      assert reward.block_height == block_height
      assert reward.maturity_height == block_height + 5  # Test environment
      assert reward.status == :immature
      assert is_integer(reward.created_at)
      assert reward.created_at > 0
    end
  end
end