defmodule Bastille.Shared.ConstantsTest do
  use ExUnit.Case, async: true

  alias Bastille.Shared.Constants

  @moduletag :unit

  describe "basic constants" do
    test "decimals returns 14 (Bastille Day)" do
      assert Constants.decimals() == 14
    end

    test "juillet per BAST is correct" do
      assert Constants.juillet_per_bast() == 100_000_000_000_000
    end

    test "block reward is 1789 BAST (Revolution year)" do
      assert Constants.block_reward_bast() == 1789
      assert Constants.block_reward_juillet() == 1789 * 100_000_000_000_000
    end

    test "max supply is infinite" do
      assert Constants.max_supply() == :infinite
    end

    test "initial supply is 1789 BAST" do
      assert Constants.initial_supply_bast() == 1789.0
      assert Constants.initial_supply_juillet() == 1789.0 * 100_000_000_000_000
    end
  end

  describe "genesis constants" do
    test "genesis address prefix is 1789" do
      assert Constants.genesis_address_prefix() == "1789"
    end

    test "genesis timestamp is July 14, 2025" do
      # July 14, 2025 at midnight UTC
      assert Constants.genesis_timestamp() == 1_752_422_400
    end
  end

  describe "fee constants" do
    test "minimum transaction fee is 1 juillet" do
      assert Constants.min_transaction_fee_juillet() == 1
    end

    test "default fee rate is 0.1%" do
      assert Constants.default_fee_rate() == 0.001
    end
  end

  describe "tokenomics summary" do
    test "returns complete tokenomics information" do
      summary = Constants.tokenomics_summary()
      
      assert summary.name == "Bastille Token"
      assert summary.symbol == "BAST"
      assert summary.decimals == 14
      assert summary.smallest_unit == "juillet"
      assert summary.max_supply == :infinite
      assert summary.model == "Utility Token (like DOGE/ETH)"
      assert summary.halving == false
      assert summary.theme == "French Revolution / Bastille Day"
      assert summary.genesis_date == "July 14, 2025"
    end
  end

  describe "supply calculations" do
    test "total supply at block height 0" do
      assert Constants.total_supply_at_block(0) == Constants.initial_supply_juillet()
    end

    test "total supply at block height 1" do
      expected = Constants.initial_supply_juillet() + Constants.block_reward_juillet()
      assert Constants.total_supply_at_block(1) == expected
    end

    test "total supply at block height 100" do
      expected = Constants.initial_supply_juillet() + (100 * Constants.block_reward_juillet())
      assert Constants.total_supply_at_block(100) == expected
    end
  end

  describe "circulating supply with burns" do
    test "circulating supply without burns equals total supply" do
      block_height = 50
      total = Constants.total_supply_at_block(block_height)
      circulating = Constants.circulating_supply_at_block(block_height, 0)
      assert circulating == total
    end

    test "circulating supply with burns" do
      block_height = 50
      burned = 1000000
      total = Constants.total_supply_at_block(block_height)
      circulating = Constants.circulating_supply_at_block(block_height, burned)
      assert circulating == total - burned
    end
  end

  describe "inflation calculations" do
    test "annual inflation rate decreases as supply increases" do
      rate_block_1 = Constants.annual_inflation_rate(1)
      rate_block_1000 = Constants.annual_inflation_rate(1000)
      
      assert rate_block_1 > rate_block_1000
    end

    test "annual inflation rate at genesis is infinite" do
      assert Constants.annual_inflation_rate(0) == :infinite
    end

    test "annual inflation rate is calculated correctly" do
      block_height = 525_600  # One year of blocks (1 min avg)
      rate = Constants.annual_inflation_rate(block_height)
      
      # Should be exactly 1.0 (100%) after one year
      assert_in_delta rate, 1.0, 0.001
    end
  end
end