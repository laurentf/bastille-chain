defmodule Bastille.Features.Tokenomics.CoinbaseMaturity do
  @moduledoc """
  Bitcoin-style coinbase maturity management for Bastille mining rewards.
  
  Reward states:
  - :immature -> Recent coinbase, non-spendable
  - :mature -> Period elapsed, spendable  
  - :orphaned -> Orphan block, reward lost
  """

  use GenServer
  require Logger

  alias Bastille.Infrastructure.Storage.CubDB.State
  alias Bastille.Features.Chain.Chain
  alias Bastille.Features.Tokenomics.Token

  # Configuration-based maturity blocks
  defp get_maturity_blocks do
    # Get from config or use environment defaults
    case Application.get_env(:bastille, :coinbase_maturity_blocks) do
      blocks when is_integer(blocks) and blocks > 0 -> blocks
      _ -> 
        # Fallback to environment-based defaults
        case Mix.env() do
          :prod -> 89   # 89 blocks for production
          _ -> 5        # 5 blocks for test/dev
        end
    end
  end

  defstruct [
    immature_coinbases: %{},  # %{block_hash => CoinbaseReward}
    maturity_blocks: nil,
    cleanup_interval_ms: 300_000  # 5 minutes
  ]

  defmodule CoinbaseReward do
    @moduledoc "Immature coinbase reward structure"
    @enforce_keys [:block_hash, :amount, :address, :block_height, :created_at]
    defstruct [
      :block_hash,      # binary() - Block hash containing coinbase
      :amount,          # integer() - Amount in juillet
      :address,         # String.t() - Miner address
      :block_height,    # integer() - Block height
      :created_at,      # integer() - Creation timestamp
      maturity_height: nil,  # integer() - Maturation height
      status: :immature      # :immature | :mature | :orphaned
    ]
  end

  # Client API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec add_coinbase_reward(binary(), integer(), String.t(), integer()) :: :ok
  def add_coinbase_reward(block_hash, amount, miner_address, block_height) do
    GenServer.call(__MODULE__, {:add_coinbase, block_hash, amount, miner_address, block_height})
  end

  @spec get_balance_breakdown(String.t()) :: %{total: integer(), mature: integer(), immature: integer()}
  def get_balance_breakdown(address) do
    GenServer.call(__MODULE__, {:balance_breakdown, address})
  end

  @spec get_immature_coinbases(String.t()) :: [CoinbaseReward.t()]
  def get_immature_coinbases(address) do
    GenServer.call(__MODULE__, {:get_immature, address})
  end

  @spec process_maturity(integer()) :: {:ok, matured: integer(), orphaned: integer()}
  def process_maturity(current_height) do
    GenServer.call(__MODULE__, {:process_maturity, current_height})
  end

  @spec mark_block_orphaned(binary()) :: :ok
  def mark_block_orphaned(block_hash) do
    GenServer.call(__MODULE__, {:mark_orphaned, block_hash})
  end

  @spec clear_all_immature() :: :ok
  def clear_all_immature do
    GenServer.call(__MODULE__, :clear_all_immature)
  end

  # GenServer Callbacks

  @impl true
  def init(_opts) do
    maturity_blocks = get_maturity_blocks()
    
    state = %__MODULE__{
      maturity_blocks: maturity_blocks,
      immature_coinbases: %{}
    }

    # Start periodic cleanup
    Process.send_after(self(), :cleanup_expired, state.cleanup_interval_ms)
    
    Logger.info("💰 CoinbaseMaturity started - maturation: #{maturity_blocks} blocks (#{maturity_blocks * 60} seconds)")
    {:ok, state}
  end

  @impl true
  def handle_call({:add_coinbase, block_hash, amount, address, height}, _from, state) do
    maturity_height = height + state.maturity_blocks
    
    reward = %CoinbaseReward{
      block_hash: block_hash,
      amount: amount,
      address: address,
      block_height: height,
      created_at: System.system_time(:second),
      maturity_height: maturity_height,
      status: :immature
    }

    new_state = %{state | 
      immature_coinbases: Map.put(state.immature_coinbases, block_hash, reward)
    }

    Logger.info("💰 Immature coinbase added: #{Token.format_bast(amount)} for #{address} (block #{height}, mature at #{maturity_height})")
    {:reply, :ok, new_state}
  end

  def handle_call({:balance_breakdown, address}, _from, state) do
    # Total balance from storage
    total_balance = case State.get_balance(address) do
      {:ok, balance} -> balance
      {:error, :not_found} -> 0
      {:error, :invalid_address} -> 0
    end

    # Immature amount for this address
    immature_amount = state.immature_coinbases
    |> Map.values()
    |> Enum.filter(&(&1.address == address and &1.status == :immature))
    |> Enum.reduce(0, &(&1.amount + &2))

    # Mature balance = total - immature
    mature_balance = max(0, total_balance - immature_amount)

    breakdown = %{
      total: total_balance,
      mature: mature_balance,
      immature: immature_amount
    }

    {:reply, breakdown, state}
  end

  def handle_call({:get_immature, address}, _from, state) do
    immature_rewards = state.immature_coinbases
    |> Map.values()
    |> Enum.filter(&(&1.address == address and &1.status == :immature))
    |> Enum.sort_by(&(&1.block_height), :desc)

    {:reply, immature_rewards, state}
  end

  def handle_call({:process_maturity, current_height}, _from, state) do
    {matured, remaining} = state.immature_coinbases
    |> Enum.split_with(fn {_hash, reward} ->
      reward.status == :immature and current_height >= reward.maturity_height
    end)

    {orphaned, still_remaining} = remaining
    |> Enum.split_with(fn {_hash, reward} ->
      reward.status == :immature and not block_still_in_chain?(reward.block_hash)
    end)

    # Process matured rewards
    matured_count = length(matured)
    Enum.each(matured, fn {_hash, reward} ->
      Logger.info("💎 Coinbase matured: #{Token.format_bast(reward.amount)} for #{reward.address} (block #{reward.block_height})")
      # Balance is already in State storage, just mark as mature
    end)

    # Process orphaned blocks
    orphaned_count = length(orphaned)
    Enum.each(orphaned, fn {_hash, reward} ->
      Logger.warning("⚠️ Coinbase orphaned: #{Token.format_bast(reward.amount)} for #{reward.address} (block #{reward.block_height})")
      
      # Remove balance from storage (reward was not deserved)
      current_balance = case State.get_balance(reward.address) do
        {:ok, balance} -> balance
        {:error, :not_found} -> 0
        {:error, :invalid_address} -> 0
      end
      State.update_balance(reward.address, max(0, current_balance - reward.amount))
    end)

    new_state = %{state | immature_coinbases: Map.new(still_remaining)}

    result = {:ok, matured: matured_count, orphaned: orphaned_count}
    {:reply, result, new_state}
  end

  def handle_call({:mark_orphaned, block_hash}, _from, state) do
    case Map.get(state.immature_coinbases, block_hash) do
      nil ->
        {:reply, :ok, state}  # Already cleaned up
      
      reward ->
        Logger.warning("⚠️ Orphan block detected: #{Token.format_bast(reward.amount)} for #{reward.address} (block #{reward.block_height})")
        
        # Remove balance immediately
        current_balance = case State.get_balance(reward.address) do
          {:ok, balance} -> balance
          {:error, :not_found} -> 0
          {:error, :invalid_address} -> 0
        end
        State.update_balance(reward.address, max(0, current_balance - reward.amount))
        
        # Remove from immature list
        new_state = %{state | immature_coinbases: Map.delete(state.immature_coinbases, block_hash)}
        {:reply, :ok, new_state}
    end
  end

  def handle_call(:clear_all_immature, _from, state) do
    Logger.info("🧹 Test cleanup: clearing all immature coinbases")
    new_state = %{state | immature_coinbases: %{}}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:cleanup_expired, state) do
    # Clean up very old entries (over 24h)
    cutoff_time = System.system_time(:second) - 86_400
    current_height = Chain.get_height()
    
    {expired, remaining} = state.immature_coinbases
    |> Enum.split_with(fn {_hash, reward} ->
      reward.created_at < cutoff_time or 
      (current_height - reward.block_height) > (state.maturity_blocks * 4)  # 4x normal period
    end)

    expired_count = length(expired)
    if expired_count > 0 do
      Logger.info("🧹 Cleanup: #{expired_count} expired coinbases removed")
      new_state = %{state | immature_coinbases: Map.new(remaining)}
      Process.send_after(self(), :cleanup_expired, state.cleanup_interval_ms)
      {:noreply, new_state}
    else
      Process.send_after(self(), :cleanup_expired, state.cleanup_interval_ms)
      {:noreply, state}
    end
  end

  # Private helpers

  defp block_still_in_chain?(block_hash) do
    # Check if block is still in main chain
    # Skip validation in test mode to avoid circular dependencies
    case Mix.env() do
      :test -> 
        # In test, assume all blocks are still valid to avoid circular GenServer calls
        true
      _ ->
        case Chain.get_block(block_hash) do
          %Bastille.Features.Block.Block{} -> true
          nil -> false
        end
    end
  end
end