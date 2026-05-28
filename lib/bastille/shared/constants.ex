defmodule Bastille.Shared.Constants do
  @moduledoc """
  Bastille Token Economics Constants and Configuration.

  🇫🇷 **Thematic Design:**
  - **14 decimal places** (for July 14th - Bastille Day!)
  - **Smallest unit:** "juillet" (July in French)
  - **Fixed reward:** 1789 BAST per block (no max supply, utility token model)
  - **No halving** - predictable utility token economics like DOGE

  ## Core Economics
  - **Max Supply:** ∞ (infinite, no cap)
  - **Block Reward:** 1789 BAST (never changes)
  - **Decimal Precision:** 14 places (Bastille Day theme)
  - **Economics Model:** Utility token (like DOGE, ETH)
  """

  # ===== DECIMAL SYSTEM =====
  # Bastille Day decimal system - 14 decimals for July 14th!
  @decimals 14
  # 10^14
  @juillet_per_bast 100_000_000_000_000

  # ===== BLOCK REWARDS =====
  # Fixed block reward (no halving, utility token model)
  # 1789 BAST per block (Revolution year!)
  @fixed_block_reward_bast 1789
  @fixed_block_reward_juillet @fixed_block_reward_bast * @juillet_per_bast

  # ===== SUPPLY ECONOMICS =====
  # No maximum supply (like DOGE)
  @max_supply :infinite
  # 1789 BAST genesis supply (1 block reward worth)
  @initial_supply_bast 1789.0
  @initial_supply_juillet @initial_supply_bast * @juillet_per_bast

  # ===== GENESIS ECONOMICS =====
  # Production/mainnet address prefix
  @genesis_address_prefix "1789"
  # July 14, 2025 at midnight UTC
  @genesis_timestamp 1_752_422_400

  # ===== FEE ECONOMICS =====
  # 1 juillet minimum
  @min_transaction_fee_juillet 1
  # 0.1% default fee rate
  @default_fee_rate 0.001

  # ===== PUBLIC API =====

  @doc "Get decimal precision (14 for Bastille Day)"
  def decimals, do: @decimals

  @doc "Get juillet per BAST conversion factor"
  def juillet_per_bast, do: @juillet_per_bast

  @doc "Get fixed block reward in BAST"
  def block_reward_bast, do: @fixed_block_reward_bast

  @doc "Get fixed block reward in juillet"
  def block_reward_juillet, do: @fixed_block_reward_juillet

  @doc "Get maximum supply (infinite)"
  def max_supply, do: @max_supply

  @doc "Get initial genesis supply in BAST"
  def initial_supply_bast, do: @initial_supply_bast

  @doc "Get initial genesis supply in juillet"
  def initial_supply_juillet, do: @initial_supply_juillet

  @doc "Get genesis address prefix"
  def genesis_address_prefix, do: @genesis_address_prefix

  @doc "Get genesis timestamp (Bastille Day 2025)"
  def genesis_timestamp, do: @genesis_timestamp

  @doc "Get minimum transaction fee in juillet"
  def min_transaction_fee_juillet, do: @min_transaction_fee_juillet

  @doc "Get default fee rate (percentage)"
  def default_fee_rate, do: @default_fee_rate

  @doc """
  Get complete tokenomics summary.
  """
  def tokenomics_summary do
    %{
      # Basic Token Info
      name: "Bastille Token",
      symbol: "BAST",
      decimals: @decimals,
      smallest_unit: "juillet",

      # Supply Economics
      max_supply: @max_supply,
      initial_supply_bast: @initial_supply_bast,
      initial_supply_juillet: @initial_supply_juillet,
      block_reward_bast: @fixed_block_reward_bast,
      block_reward_juillet: @fixed_block_reward_juillet,

      # Economic Model
      model: "Utility Token (like DOGE/ETH)",
      halving: false,
      inflation: "Fixed 1789 BAST per block",

      # Theme
      theme: "French Revolution / Bastille Day",
      genesis_date: "July 14, 2025",
      genesis_timestamp: @genesis_timestamp,

      # Fees
      min_fee_juillet: @min_transaction_fee_juillet,
      default_fee_rate: @default_fee_rate
    }
  end

  @doc """
  Calculate total supply at given block height.

  Formula: initial_supply + (block_height * block_reward)
  """
  def total_supply_at_block(block_height) when is_integer(block_height) and block_height >= 0 do
    @initial_supply_juillet + block_height * @fixed_block_reward_juillet
  end

  @doc """
  Calculate circulating supply at given block height with burns.

  Formula: total_supply - total_burned
  """
  def circulating_supply_at_block(block_height, total_burned_juillet \\ 0) do
    total_supply_at_block(block_height) - total_burned_juillet
  end

  @doc """
  Get annual inflation rate at given block height.

  Since block reward is fixed, inflation rate decreases over time.
  Assumes ~525,600 blocks per year (1 minute avg block time).
  """
  def annual_inflation_rate(block_height) when block_height > 0 do
    annual_new_supply = 525_600 * @fixed_block_reward_juillet
    current_supply = total_supply_at_block(block_height)
    annual_new_supply / current_supply
  end

  # Genesis case
  def annual_inflation_rate(0), do: :infinite
end
