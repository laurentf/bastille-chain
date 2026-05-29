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

  defstruct [
    :mining_address,
    :mining_enabled,
    # :idle | :mining
    mining_state: :idle
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
  Gets the current mining status. Lock-free read via :persistent_term so that
  RPC endpoints stay responsive while this GenServer is busy mining a block.
  """
  @spec mining_status() :: %{enabled: boolean(), address: binary() | nil}
  def mining_status do
    case :persistent_term.get({__MODULE__, :status}, nil) do
      %{} = cached -> cached
      _ -> GenServer.call(__MODULE__, :mining_status)
    end
  end

  @doc """
  Manually mines a single block.
  """
  @spec mine_block(binary()) :: {:ok, Block.t()} | {:error, term()}
  def mine_block(mining_address) do
    GenServer.call(__MODULE__, {:mine_block, mining_address}, :infinity)
  end

  @doc """
  Validates a transaction. Runs in the caller's process — no GenServer.call —
  so incoming P2P transactions can still be validated while we are mining a
  block locally.
  """
  @spec validate_transaction(Transaction.t()) :: :ok | {:error, term()}
  def validate_transaction(%Bastille.Features.Transaction.Transaction{} = tx) do
    validate_transaction_full(tx)
  end

  @doc """
  Validates a block. Same reasoning as validate_transaction/1 — runs inline.
  """
  @spec validate_block(Block.t()) :: :ok | {:error, term()}
  def validate_block(%Bastille.Features.Block.Block{} = block) do
    validate_block_full(block)
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

    publish_mining_status(final_state)

    Logger.info(
      "🎯 Validator started: mining #{if mining_enabled, do: "enabled", else: "disabled"}"
    )

    {:ok, final_state}
  end

  @impl true
  def handle_call({:start_mining, mining_address}, _from, state) do
    case state.mining_state do
      :idle ->
        new_state =
          %{state | mining_address: mining_address, mining_enabled: true, mining_state: :mining}
          |> start_mining_task()

        publish_mining_status(new_state)
        Logger.info("🎯 Mining started to address: #{Base.encode16(mining_address, case: :lower)}")
        {:reply, :ok, new_state}

      _other_state ->
        {:reply, {:error, :already_mining}, state}
    end
  end

  @impl true
  def handle_call(:stop_mining, _from, state) do
    new_state = %{state | mining_enabled: false, mining_state: :idle}
    publish_mining_status(new_state)
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
            # Chain.add_block purges the block's txs from the mempool.
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

  # validate_transaction/1 and validate_block/1 now run in the caller process
  # (no handle_call) so they don't queue behind the mining handler.

  @impl true
  def handle_info(:mine_next_block, %{mining_enabled: false} = state) do
    {:noreply, state}
  end

  def handle_info(:mine_next_block, %{mining_state: :mining} = state) do
    # Already mining, ignore
    {:noreply, state}
  end

  def handle_info(
        :mine_next_block,
        %{mining_state: :idle, mining_enabled: true, mining_address: address} = state
      )
      when is_binary(address) do
    # Mining runs synchronously inside this handler. RPC status calls don't
    # block because mining_status is published to :persistent_term and the
    # consensus engine isn't held during the hot loop (see Consensus.Engine).
    new_state = %{state | mining_state: :mining}
    publish_mining_status(new_state)

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
            # Chain.add_block purges the block's txs from the mempool.
            schedule_next(state, 100)

          {:orphan, :added_to_pool} ->
            Logger.info("🔄 MINED BLOCK BECAME ORPHAN - added to orphan pool")
            schedule_next(state, 100)

          {:orphan, parent_hash} ->
            Logger.info("🔄 MINED BLOCK BECAME ORPHAN - waiting for parent")

            Logger.info(
              "   └─ Missing parent: #{Base.encode16(parent_hash) |> String.slice(0, 8)}..."
            )

            schedule_next(state, 100)

          {:error, reason} ->
            Logger.error("❌ BLOCK REJECTED BY BLOCKCHAIN!")
            Logger.error("   └─ Reason: #{inspect(reason)}")
            schedule_next(state, 1000)
        end

      {:error, reason} ->
        Logger.error("❌ MINING FAILED!")
        Logger.error("   └─ Reason: #{inspect(reason)}")
        schedule_next(state, 1000)
    end
  end

  def handle_info(:mine_next_block, state) do
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

    Logger.info(
      "   └─ Block reward: #{Token.fixed_reward_juillet()} juillet (#{Token.fixed_reward()} BAST)"
    )

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

    Logger.info(
      "   └─ Previous block hash: #{if head_block, do: "#{Base.encode16(head_block.hash, case: :lower) |> String.slice(0, 16)}...", else: "genesis"}"
    )

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

    difficulty =
      if height == 0 do
        # Genesis block: start easy for testing
        Logger.info("🚀 Genesis block detected - Using minimal difficulty 1")

        # FORCE the consensus engine to use difficulty 1 for genesis
        Consensus.Engine.set_difficulty(1)
        1
      else
        # Delegate the actual adjustment to the consensus engine. It respects
        # `difficulty_adjustment_interval` (no change between adjustment points)
        # and caps the change factor — bypassing it here caused the difficulty
        # to multiply on every single block and explode (1 → 65536 in ~9 blocks).
        # We exclude genesis (index 0) from the window so its symbolic timestamp
        # doesn't poison the actual-time calculation.
        recent_block_times =
          Chain.get_recent_block_times(10)
          |> Enum.reject(&(&1.index == 0))

        current_difficulty = Consensus.Engine.get_difficulty()
        new_difficulty = Consensus.Engine.adjust_difficulty_fast(recent_block_times)

        if new_difficulty != current_difficulty do
          Logger.info("🎯 Difficulty adjusted: #{current_difficulty} → #{new_difficulty}")
        end

        new_difficulty
      end

    Logger.info("🔨 CREATING BLOCK TEMPLATE")
    Logger.info("   └─ Block index: #{height + 1}")
    Logger.info("   └─ Final difficulty: #{difficulty}")
    Logger.info("   └─ Number of transactions: #{length(all_transactions)}")

    # Create block template with dynamic difficulty
    block_template =
      Block.new(
        index: height + 1,
        previous_hash: if(head_block, do: head_block.hash, else: <<0::256>>),
        transactions: all_transactions,
        difficulty: difficulty
      )

    Logger.info("📋 Block template created successfully")

    Logger.info(
      "   └─ Previous hash: #{Base.encode16(block_template.header.previous_hash, case: :lower) |> String.slice(0, 16)}..."
    )

    Logger.info(
      "   └─ Merkle root: #{Base.encode16(block_template.header.merkle_root, case: :lower) |> String.slice(0, 16)}..."
    )

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

        Logger.info(
          "   └─ Block hash: #{Base.encode16(mined_block.hash, case: :lower) |> String.slice(0, 32)}..."
        )

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
    header_valid =
      case block.header do
        %{index: i, timestamp: t, difficulty: d}
        when is_integer(i) and i >= 0 and is_integer(t) and is_integer(d) and d > 0 ->
          Logger.info("   ✅ Header valid")
          true

        _ ->
          Logger.error("   ❌ Header invalid")
          false
      end

    transactions_valid = Enum.all?(block.transactions, &Transaction.valid?/1)

    Logger.info(
      "   #{if transactions_valid, do: "✅", else: "❌"} Transactions valid: #{transactions_valid}"
    )

    # Test merkle root
    expected_block = Block.calculate_merkle_root(block)
    merkle_valid = block.header.merkle_root == expected_block.header.merkle_root
    Logger.info("   #{if merkle_valid, do: "✅", else: "❌"} Merkle root valid: #{merkle_valid}")

    if not merkle_valid do
      Logger.error(
        "   └─ Expected: #{Base.encode16(expected_block.header.merkle_root, case: :lower) |> String.slice(0, 16)}..."
      )

      Logger.error(
        "   └─ Received: #{Base.encode16(block.header.merkle_root, case: :lower) |> String.slice(0, 16)}..."
      )
    end

    # Test hash
    expected_hash_block = Block.calculate_hash(%{block | hash: nil})
    hash_valid = block.hash == expected_hash_block.hash
    Logger.info("   #{if hash_valid, do: "✅", else: "❌"} Hash valid: #{hash_valid}")

    if not hash_valid do
      Logger.error(
        "   └─ Expected hash: #{Base.encode16(expected_hash_block.hash, case: :lower) |> String.slice(0, 16)}..."
      )

      Logger.error(
        "   └─ Received hash: #{Base.encode16(block.hash, case: :lower) |> String.slice(0, 16)}..."
      )
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

  defp format_hash(hash) when is_binary(hash) do
    hash |> Base.encode16(case: :lower) |> String.slice(0, 32)
  end

  defp format_hash(_), do: "invalid_hash"

  # Reschedule the mining loop and publish the new (idle) status for lock-free
  # readers. Mining runs in this GenServer's message-handler, so during mining
  # any GenServer.call against us blocks — we publish to :persistent_term so
  # status queries don't time out.
  defp schedule_next(state, delay_ms) do
    final_state = %{state | mining_state: :idle}
    publish_mining_status(final_state)

    if final_state.mining_enabled do
      Process.send_after(self(), :mine_next_block, delay_ms)
    end

    {:noreply, final_state}
  end

  defp publish_mining_status(%__MODULE__{} = state) do
    :persistent_term.put({__MODULE__, :status}, %{
      enabled: state.mining_enabled,
      address: state.mining_address,
      state: state.mining_state
    })
  end
end
