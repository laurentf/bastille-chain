defmodule Bastille.Features.Mining.MiningCoordinator do
  @moduledoc """
  Validator GenServer for block and transaction validation.

  Handles mining new blocks, validating transactions, and managing
  the mining process with configurable mining address.
  """

  use GenServer
  require Logger

  alias Bastille.Features.Block.Block
  alias Bastille.Features.Tokenomics.Token
  alias Bastille.Features.Transaction.Transaction
  alias Bastille.Features.Chain.Chain
  alias Bastille.Features.Transaction.Mempool
  alias Bastille.Features.Consensus, as: Consensus

  # Constants
  @min_block_time_ms 1000  # Minimum 1 second for safety in difficulty calculation

  defstruct [
    :mining_address,
    :mining_enabled,
    mining_state: :idle  # :idle | :mining
  ]

  @type t :: %__MODULE__{
    mining_address: binary() | nil,
    mining_enabled: boolean(),
    mining_state: :idle | :mining
  }

  # Note: block_reward is now a protocol constant from Token module

  # Client API

  @doc """
  Starts the validator server.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Starts mining blocks.
  """
  @spec start_mining(binary()) :: :ok | {:error, term()}
  def start_mining(mining_address) do
    GenServer.call(__MODULE__, {:start_mining, mining_address})
  end

  @doc """
  Stops mining blocks.
  """
  @spec stop_mining() :: :ok
  def stop_mining do
    GenServer.call(__MODULE__, :stop_mining)
  end

  @doc """
  Gets the current mining status.
  """
  @spec mining_status() :: %{enabled: boolean(), address: binary() | nil}
  def mining_status do
    GenServer.call(__MODULE__, :mining_status)
  end

  @doc """
  Manually mines a single block.
  """
  @spec mine_block(binary()) :: {:ok, Block.t()} | {:error, term()}
  def mine_block(mining_address) do
    GenServer.call(__MODULE__, {:mine_block, mining_address}, :infinity)
  end

  @doc """
  Validates a transaction.
  """
  @spec validate_transaction(Transaction.t()) :: :ok | {:error, term()}
  def validate_transaction(%Bastille.Features.Transaction.Transaction{} = tx) do
    GenServer.call(__MODULE__, {:validate_transaction, tx})
  end

  @doc """
  Validates a block.
  """
  @spec validate_block(Block.t()) :: :ok | {:error, term()}
  def validate_block(%Bastille.Features.Block.Block{} = block) do
    GenServer.call(__MODULE__, {:validate_block, block})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    mining_address = Keyword.get(opts, :mining_address)
    mining_enabled = Keyword.get(opts, :mining_enabled, false)

    state = %__MODULE__{
      mining_address: mining_address,
      mining_enabled: mining_enabled,
      mining_state: :idle
    }

    # Start mining if enabled and address provided
    final_state =
      if mining_enabled and mining_address do
        start_mining_task(state)
      else
        state
      end

    Logger.info("🎯 Validator started: mining #{if mining_enabled, do: "enabled", else: "disabled"}")
    {:ok, final_state}
  end

  @impl true
  def handle_call({:start_mining, mining_address}, _from, state) do
    case state.mining_state do
      :idle ->
        new_state = %{state |
          mining_address: mining_address,
          mining_enabled: true,
          mining_state: :mining
        }
        |> start_mining_task()

        Logger.info("🎯 Mining started to address: #{Base.encode16(mining_address, case: :lower)}")
        {:reply, :ok, new_state}

      _other_state ->
        {:reply, {:error, :already_mining}, state}
    end
  end

  @impl true
  def handle_call(:stop_mining, _from, state) do
    new_state = %{state | mining_enabled: false, mining_state: :idle}
    Logger.info("⏹️ Mining stopped by request")
    {:reply, :ok, new_state}
  end

  def handle_call(:mining_status, _from, state) do
    status = %{
      enabled: state.mining_enabled,
      address: state.mining_address
    }
    {:reply, status, state}
  end

  def handle_call({:mine_block, mining_address}, _from, state) do
    case create_and_mine_block(mining_address) do
      {:ok, block} ->
    case Chain.add_block(block) do
          :ok ->
            # Remove mined transactions from mempool
            tx_hashes = Enum.map(block.transactions, & &1.hash)
            Mempool.remove_transactions(tx_hashes)

            Logger.info("Successfully mined block #{block.header.index}")
            {:reply, {:ok, block}, state}

          {:error, reason} = error ->
            Logger.error("Failed to add mined block: #{inspect(reason)}")
            {:reply, error, state}
        end

      {:error, reason} = error ->
        Logger.error("Failed to mine block: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  def handle_call({:validate_transaction, %Bastille.Features.Transaction.Transaction{} = tx}, _from, %__MODULE__{} = state) do
    result = validate_transaction_full(tx)
    {:reply, result, state}
  end

  def handle_call({:validate_block, %Bastille.Features.Block.Block{} = block}, _from, %__MODULE__{} = state) do
    result = validate_block_full(block)
    {:reply, result, state}
  end

  @impl true
  def handle_info(:mine_next_block, %{mining_enabled: false} = state) do
    {:noreply, state}
  end

  def handle_info(:mine_next_block, %{mining_state: :mining} = state) do
    # Already mining, ignore
    {:noreply, state}
  end

  def handle_info(:mine_next_block, %{mining_state: :idle, mining_enabled: true, mining_address: address} = state)
      when is_binary(address) do
    # Start mining synchronously
    new_state = %{state | mining_state: :mining}

    case create_and_mine_block(address) do
      {:ok, block} ->
        Logger.info("🎉 BLOCK MINED SUCCESSFULLY!")
        Logger.info("   └─ Block index: #{block.header.index}")
        Logger.info("   └─ Hash: #{block.hash |> format_hash()}")
        Logger.info("   └─ Nonce: #{block.header.nonce}")
        Logger.info("   └─ Transactions: #{length(block.transactions)}")

        # Submit to blockchain
        case Bastille.Features.Chain.Chain.add_block(block) do
          :ok ->
            # Remove mined transactions from mempool
            block.transactions
            |> Enum.map(& &1.hash)
            |> tap(&Mempool.remove_transactions/1)
            |> length()
            |> then(&Logger.info("🗑️ Mempool cleanup: #{&1} transactions removed"))

            # Schedule next mining cycle
            final_state = %{new_state | mining_state: :idle}
            if final_state.mining_enabled do
              Process.send_after(self(), :mine_next_block, 100)  # Small delay between blocks
            end
            {:noreply, final_state}

          {:orphan, :added_to_pool} ->
            Logger.info("🔄 MINED BLOCK BECAME ORPHAN - added to orphan pool")
            Logger.info("   └─ Block will be processed when parent arrives")

            # Continue mining - this is normal in concurrent environments
            final_state = %{new_state | mining_state: :idle}
            if final_state.mining_enabled do
              Process.send_after(self(), :mine_next_block, 100)  # Quick retry for orphan
            end
            {:noreply, final_state}

          {:orphan, parent_hash} ->
            Logger.info("🔄 MINED BLOCK BECAME ORPHAN - waiting for parent")
            Logger.info("   └─ Missing parent: #{Base.encode16(parent_hash) |> String.slice(0, 8)}...")

            # Continue mining - this is normal in concurrent environments
            final_state = %{new_state | mining_state: :idle}
            if final_state.mining_enabled do
              Process.send_after(self(), :mine_next_block, 100)  # Quick retry for orphan
            end
            {:noreply, final_state}

          {:error, reason} ->
            Logger.error("❌ BLOCK REJECTED BY BLOCKCHAIN!")
            Logger.error("   └─ Reason: #{inspect(reason)}")

            # Retry after error
            final_state = %{new_state | mining_state: :idle}
            if final_state.mining_enabled do
              Process.send_after(self(), :mine_next_block, 1000)  # Longer delay after error
            end
            {:noreply, final_state}
        end

      {:error, reason} ->
        Logger.error("❌ MINING FAILED!")
        Logger.error("   └─ Reason: #{inspect(reason)}")

        # Retry after error
        final_state = %{new_state | mining_state: :idle}
        if final_state.mining_enabled do
          Process.send_after(self(), :mine_next_block, 1000)  # Longer delay after error
        end
        {:noreply, final_state}
    end
  end

  def handle_info(:mine_next_block, state) do
    # No address configured, can't mine
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private functions

  defp start_mining_task(%__MODULE__{mining_address: nil} = state), do: state

  defp start_mining_task(%__MODULE__{mining_address: address} = state) do
    Logger.info("🚀 STARTING MINING CYCLE")
    Logger.info("   └─ Mining address: #{address}")
    Logger.info("   └─ Block reward: #{Token.fixed_reward_juillet()} juillet (#{Token.fixed_reward()} BAST)")

    # Start the mining cycle
    Process.send_after(self(), :mine_next_block, 100)
    state
  end

  defp create_and_mine_block(mining_address) do
    Logger.info("⛏️ 🔥 STARTING MINING PROCESS")
    Logger.info("📍 Mining address: #{mining_address}")

    # Get current blockchain state
    head_block = Chain.get_head_block()
    height = Chain.get_height()

    Logger.info("🔗 Blockchain state:")
    Logger.info("   └─ Current height: #{height}")
    Logger.info("   └─ Previous block hash: #{if head_block, do: "#{Base.encode16(head_block.hash, case: :lower) |> String.slice(0, 16)}...", else: "genesis"}")

    # Get transactions from mempool
    pending_transactions = Mempool.get_transactions(100)
    Logger.info("📦 Mempool transactions: #{length(pending_transactions)} transactions retrieved")

    # BITCOIN-LIKE MINING: Always mine blocks, even if empty
    # =====================================================
    # Bitcoin always mines blocks and rewards miners via coinbase transaction
    # This ensures consistent block production and network security

    Logger.info("⚡ BITCOIN-LIKE MINING: Mining block #{height + 1}")
    Logger.info("   └─ Transactions: #{length(pending_transactions)}")
    Logger.info("   └─ Always mine for network security and rewards")

    # Create coinbase transaction with fee collection (burn disabled)
    coinbase_tx = Transaction.coinbase_with_fees(mining_address, height + 1, pending_transactions)
    Logger.info("💰 Coinbase transaction created - Total reward: #{coinbase_tx.amount} juillet")

    # Log fee collection summary (burn disabled)
    total_fees = Enum.reduce(pending_transactions, 0, fn tx, acc -> acc + tx.fee end)
    if total_fees > 0 do
      Logger.info("💸 Fee total collected: #{total_fees} juillet (100% to miner; burn disabled)")
    end

    # Combine transactions
    all_transactions = [coinbase_tx | pending_transactions]
    Logger.info("📋 Total transactions in block: #{length(all_transactions)}")

    # BITCOIN-STYLE DYNAMIC DIFFICULTY ADJUSTMENT
    # ===========================================
    # 1. For genesis block (height 0), start with difficulty 1 for fast testing
    # 2. For subsequent blocks, adjust based on actual vs target time
    # 3. Limit changes to prevent wild oscillations

    Logger.info("🎯 CALCULATING DYNAMIC DIFFICULTY")

    difficulty = if height == 0 do
      # Genesis block: start easy for testing
      Logger.info("🚀 Genesis block detected - Using minimal difficulty 1")

      # FORCE the consensus engine to use difficulty 1 for genesis
      Consensus.Engine.set_difficulty(1)
      1
    else
      Logger.info("📊 Analyzing recent blocks for automatic adjustment...")
      # Get recent block times for lightweight time-based adjustment (OPTIMIZED)
      recent_block_times = Chain.get_recent_block_times(10)

      if length(recent_block_times) >= 2 do
        # Calculate actual vs target time (Bitcoin-style)
        actual_time = calculate_block_time_average_from_times(recent_block_times)
        # Get target time from consensus configuration instead of hardcoded value
        consensus_info = Consensus.Engine.info()
        target_time = Map.get(consensus_info, :target_block_time, 10_000)

        current_difficulty = Consensus.Engine.get_difficulty()

        # Bitcoin-style adjustment: difficulty = old_difficulty × (target_time / actual_time)
        # Protect against division by zero or negative times
        safe_actual_time = max(@min_block_time_ms, actual_time)  # Minimum 1 second
        time_ratio = target_time / safe_actual_time

        # Limit adjustment to prevent wild swings (max 4x change like Bitcoin)
        limited_ratio = max(0.25, min(4.0, time_ratio))

        new_difficulty = max(1, round(current_difficulty * limited_ratio))

        Logger.info("🎯 Dynamic difficulty adjustment: #{current_difficulty} → #{new_difficulty}")
        Logger.info("   └─ Actual block time: #{round(actual_time)}ms, Target: #{target_time}ms")
        Logger.info("   └─ Time ratio: #{Float.round(time_ratio, 3)}, Limited ratio: #{Float.round(limited_ratio, 3)}")

        # Update consensus engine with new difficulty (FAST API)
        Consensus.Engine.adjust_difficulty_fast(recent_block_times)
        new_difficulty
      else
        # Not enough blocks yet, use current difficulty
        current = Consensus.Engine.get_difficulty()
        Logger.info("� Using current difficulty #{current} (not enough blocks for adjustment)")
        current
      end
    end

    Logger.info("🔨 CREATING BLOCK TEMPLATE")
    Logger.info("   └─ Block index: #{height + 1}")
    Logger.info("   └─ Final difficulty: #{difficulty}")
    Logger.info("   └─ Number of transactions: #{length(all_transactions)}")

    # Create block template with dynamic difficulty
    block_template = Block.new([
      index: height + 1,
      previous_hash: if(head_block, do: head_block.hash, else: <<0::256>>),
      transactions: all_transactions,
      difficulty: difficulty
    ])

    Logger.info("📋 Block template created successfully")
    Logger.info("   └─ Previous hash: #{Base.encode16(block_template.header.previous_hash, case: :lower) |> String.slice(0, 16)}...")
    Logger.info("   └─ Merkle root: #{Base.encode16(block_template.header.merkle_root, case: :lower) |> String.slice(0, 16)}...")

    Logger.info("⚡ STARTING BLAKE3 MINING")
    Logger.info("   └─ Algorithm: Blake3 (ultra-fast)")
    Logger.info("   └─ Target difficulty: #{difficulty}")
    Logger.info("   └─ Starting nonce search...")

    # Mine the block using consensus engine
    mining_start_time = System.monotonic_time(:millisecond)
    result = Consensus.Engine.mine_block(block_template)
    mining_end_time = System.monotonic_time(:millisecond)
    mining_duration = mining_end_time - mining_start_time

    case result do
      {:ok, mined_block} ->
        Logger.info("🎉 BLOCK SUCCESSFULLY MINED!")
        Logger.info("   └─ Mining duration: #{mining_duration}ms")
        Logger.info("   └─ Found nonce: #{mined_block.header.nonce}")
        Logger.info("   └─ Block hash: #{Base.encode16(mined_block.hash, case: :lower) |> String.slice(0, 32)}...")
        Logger.info("   └─ Verifying proof of work...")

        {:ok, mined_block}

      {:error, reason} ->
        Logger.error("❌ MINING FAILED!")
        Logger.error("   └─ Attempted duration: #{mining_duration}ms")
        Logger.error("   └─ Reason: #{inspect(reason)}")

        {:error, reason}
    end
  end

  defp validate_transaction_full(%Bastille.Features.Transaction.Transaction{} = tx) do
    with :ok <- validate_transaction_structure(tx),
         :ok <- validate_transaction_signature(tx),
         :ok <- Chain.validate_transaction(tx) do
      :ok
    else
      error -> error
    end
  end

  defp validate_block_full(%Bastille.Features.Block.Block{} = block) do
    with :ok <- validate_block_structure(block),
         :ok <- validate_block_transactions(block),
         :ok <- Consensus.Engine.validate_block(block) do
      :ok
    else
      error -> error
    end
  end

  defp validate_transaction_structure(%Bastille.Features.Transaction.Transaction{} = tx) do
    if Transaction.valid?(tx) do
      :ok
    else
      {:error, :invalid_transaction_structure}
    end
  end

  defp validate_transaction_signature(%Bastille.Features.Transaction.Transaction{} = tx) do
    if Transaction.verify_signature(tx) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end

  defp validate_block_structure(%Bastille.Features.Block.Block{} = block) do
    Logger.info("🔍 DETAILED BLOCK STRUCTURE VALIDATION")
    Logger.info("   └─ Index: #{block.header.index}")
    Logger.info("   └─ Timestamp: #{block.header.timestamp}")
    Logger.info("   └─ Difficulty: #{block.header.difficulty}")
    Logger.info("   └─ Nonce: #{block.header.nonce}")
    Logger.info("   └─ Number of transactions: #{length(block.transactions)}")

    # Step-by-step testing
    header_valid = case block.header do
      %{index: i, timestamp: t, difficulty: d}
        when is_integer(i) and i >= 0 and is_integer(t) and is_integer(d) and d > 0 ->
        Logger.info("   ✅ Header valid")
        true
      _ ->
        Logger.error("   ❌ Header invalid")
        false
    end

    transactions_valid = Enum.all?(block.transactions, &Transaction.valid?/1)
    Logger.info("   #{if transactions_valid, do: "✅", else: "❌"} Transactions valid: #{transactions_valid}")

    # Test merkle root
    expected_block = Block.calculate_merkle_root(block)
    merkle_valid = block.header.merkle_root == expected_block.header.merkle_root
    Logger.info("   #{if merkle_valid, do: "✅", else: "❌"} Merkle root valid: #{merkle_valid}")
    if not merkle_valid do
      Logger.error("   └─ Expected: #{Base.encode16(expected_block.header.merkle_root, case: :lower) |> String.slice(0, 16)}...")
      Logger.error("   └─ Received: #{Base.encode16(block.header.merkle_root, case: :lower) |> String.slice(0, 16)}...")
    end

    # Test hash
    expected_hash_block = Block.calculate_hash(%{block | hash: nil})
    hash_valid = block.hash == expected_hash_block.hash
    Logger.info("   #{if hash_valid, do: "✅", else: "❌"} Hash valid: #{hash_valid}")
    if not hash_valid do
      Logger.error("   └─ Expected hash: #{Base.encode16(expected_hash_block.hash, case: :lower) |> String.slice(0, 16)}...")
      Logger.error("   └─ Received hash: #{Base.encode16(block.hash, case: :lower) |> String.slice(0, 16)}...")
    end

    overall_valid = header_valid and transactions_valid and merkle_valid and hash_valid
    Logger.info("   🎯 Overall result: #{if overall_valid, do: "✅ VALID", else: "❌ INVALID"}")

    if overall_valid do
      :ok
    else
      {:error, :invalid_block_structure}
    end
  end

  defp validate_block_transactions(%Bastille.Features.Block.Block{transactions: transactions}) do
    Enum.reduce_while(transactions, :ok, fn tx, _acc ->
      case validate_transaction_full(tx) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  # Optimized block time calculation using only timestamps (MUCH FASTER)
  defp calculate_block_time_average_from_times(block_times) when length(block_times) < 2, do: 10_000  # Default 10s
  defp calculate_block_time_average_from_times(block_times) do
    # Sort by index to ensure chronological order
    sorted_times = Enum.sort_by(block_times, & &1.index)

    # Calculate time differences between consecutive blocks using actual timestamps
    time_diffs =
      sorted_times
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [prev, curr] ->
        curr.timestamp - prev.timestamp
      end)

    # Return average time in milliseconds
    if length(time_diffs) > 0 do
      average = Enum.sum(time_diffs) / length(time_diffs)
      # Protect against zero or negative times (clock issues, same timestamps)
      max(@min_block_time_ms, average)  # Minimum 1 second between blocks
    else
      10_000  # Default 10 seconds
    end
  end



  defp format_hash(hash) when is_binary(hash) do
    hash |> Base.encode16(case: :lower) |> String.slice(0, 32)
  end
  defp format_hash(_), do: "invalid_hash"
end
