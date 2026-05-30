defmodule Bastille.Features.Chain.Chain do
  @moduledoc """
  Blockchain Chain GenServer.

  Manages the blockchain state, validates and adds new blocks,
  and provides query interface for the chain.

  Now supports:
  - "1789..." Bastille address format
  - Post-quantum transaction validation
  - String-based address tracking
  - Modern 4-database storage architecture (RocksDB-compatible)
  """

  use GenServer
  require Logger

  alias Bastille.Features.Consensus, as: Consensus
  alias Bastille.Features.Block.Block
  alias Bastille.Features.Mining.Mining
  alias Bastille.Features.Transaction.Transaction
  alias Bastille.Infrastructure.Storage.CubDB.{Blocks, Chain, Index, State}
  # Mempool referenced through its public API where needed
  alias Bastille.Features.Chain.{OrphanManager, TransactionValidator}

  defstruct [
    :blocks,
    :height,
    :head_hash
    # balances and nonces now accessed directly from State storage
  ]

  @type t :: %__MODULE__{
          blocks: [Block.t()],
          height: non_neg_integer(),
          head_hash: binary()
          # balances and nonces accessed directly from State storage - no in-memory duplication
        }

  # Max reorg depth: how many recent blocks keep a rollback journal.
  @max_reorg_depth 100

  # Client API

  @doc """
  Starts the blockchain chain.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets the current blockchain state.
  """
  @spec get_state() :: t()
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  @doc """
  Gets the current blockchain height.
  """
  @spec get_height() :: non_neg_integer()
  def get_height do
    GenServer.call(__MODULE__, :get_height)
  end

  @doc """
  Gets the head block.
  """
  @spec get_head_block() :: Block.t() | nil
  def get_head_block do
    GenServer.call(__MODULE__, :get_head_block)
  end

  @doc """
  Gets a block by hash.
  """
  @spec get_block(binary()) :: Block.t() | nil
  def get_block(hash) do
    GenServer.call(__MODULE__, {:get_block, hash})
  end

  @doc """
  Gets the balance for an address.
  """
  @spec get_balance(String.t()) :: non_neg_integer()
  def get_balance(address) do
    # Use State storage directly instead of GenServer memory cache
    case State.get_balance(address) do
      {:ok, balance} -> balance
      {:error, :not_found} -> 0
      # Return 0 for invalid addresses
      {:error, :invalid_address} -> 0
    end
  end

  @doc """
  Gets the nonce for an address.
  """
  @spec get_nonce(String.t()) :: non_neg_integer()
  def get_nonce(address) do
    # Use State storage directly instead of GenServer memory cache
    case State.get_nonce(address) do
      {:ok, nonce} -> nonce
      {:error, :not_found} -> 0
      # Return 0 for invalid addresses
      {:error, :invalid_address} -> 0
    end
  end

  @doc """
  Adds a new block to the chain.
  """
  @spec add_block(Block.t()) :: :ok | {:error, term()}
  def add_block(%Bastille.Features.Block.Block{} = block) do
    GenServer.call(__MODULE__, {:add_block, block})
  end

  @doc """
  Switch the chain onto a heavier alternative fork (Sprint 4.4).

  Takes the `result` map produced by `Bastille.Features.Chain.ReorgSearch`
  once a common ancestor has been found. The current chain is rolled back to
  that ancestor (`State.rollback_block` per block), then the fork is applied
  block by block under full validation.

  The switch is all-or-nothing: if any fork block fails to apply, the partially
  applied fork is undone and the original chain is re-applied, so the node ends
  up exactly where it started. Returns `{:ok, summary}` on a completed switch,
  or `{:error, reason}` if the fork is not heavier (`:not_better`), its ancestor
  is no longer in the in-memory window (`:ancestor_not_in_memory`), or a fork
  block fails validation (original chain kept).
  """
  @spec reorganize(map()) :: {:ok, map()} | {:error, term()}
  def reorganize(%{better?: _, ancestor_hash: _, fork_chain: _} = result) do
    GenServer.call(__MODULE__, {:reorganize, result}, 60_000)
  end

  @doc """
  Validates a transaction against the current chain state.

  Runs in the caller's process — does NOT take a `GenServer.call(Chain, …)`.
  Validation reads `State` directly via the pure
  `Bastille.Features.Chain.TransactionValidator`, so callers (mempool,
  miner, RPC) don't queue behind a long-running `add_block` on the Chain
  GenServer.
  """
  @spec validate_transaction(Transaction.t()) :: :ok | {:error, term()}
  def validate_transaction(%Bastille.Features.Transaction.Transaction{} = tx) do
    TransactionValidator.validate(tx)
  end

  @doc """
  Gets the transactions for an address.
  """
  @spec get_transactions_for_address(String.t()) :: [Transaction.t()]
  def get_transactions_for_address(address) do
    GenServer.call(__MODULE__, {:get_transactions_for_address, address})
  end

  @doc """
  Gets all balances for debugging/testing only.

  ⚠️  WARNING: This is for testing/debugging only!
      Do not use in production code - use get_balance/1 for individual accounts.
  """
  @spec get_all_balances() :: %{String.t() => non_neg_integer()}
  def get_all_balances do
    GenServer.call(__MODULE__, :get_all_balances)
  end

  @doc """
  Gets all blocks (limited for performance).
  """
  @spec get_all_blocks() :: [Block.t()]
  def get_all_blocks do
    GenServer.call(__MODULE__, :get_all_blocks)
  end

  @doc """
  Get block hash at specific height.
  """
  @spec get_block_hash_at_height(non_neg_integer()) :: {:ok, binary()} | {:error, :not_found}
  def get_block_hash_at_height(height) do
    Chain.get_block_hash_at_height(height)
  end

  @doc """
  Get recent blocks for difficulty calculation.
  """
  @spec get_recent_blocks(pos_integer()) :: [Block.t()]
  def get_recent_blocks(count) do
    GenServer.call(__MODULE__, {:get_recent_blocks, count})
  end

  @doc """
  Get recent block timestamps and indexes for difficulty calculation (lightweight).
  Returns only the essential data needed for difficulty adjustment.
  """
  @spec get_recent_block_times(pos_integer()) :: [
          %{index: non_neg_integer(), timestamp: integer()}
        ]
  def get_recent_block_times(count) do
    GenServer.call(__MODULE__, {:get_recent_block_times, count})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    case load_blockchain_from_new_storage() do
      {:ok, state} ->
        Logger.info("🔗 Loaded blockchain from 4-database storage, height: #{state.height}")
        {:ok, state}

      {:error, :not_found} ->
        Logger.info("🏰═══════════════════════════════════════════════════════════════")
        Logger.info("🏰  BASTILLE BLOCKCHAIN GENESIS - LIBERTÉ, ÉGALITÉ, FRATERNITÉ 🇫🇷")
        Logger.info("🏰═══════════════════════════════════════════════════════════════")
        Logger.info("🆕 No blockchain found, creating hardcoded Bastille genesis block")
        Logger.info("🏛️ Genesis: Bastille Day 2025 - July 14th Revolution!")

        # Create the hardcoded genesis block (not mined!)
        genesis_block = Block.genesis()
        genesis_tx = hd(genesis_block.transactions)

        Logger.info("🎯 GENESIS BLOCK SPECIFICATION:")
        Logger.info("   ├─ Index: #{genesis_block.header.index} (The Beginning)")

        Logger.info(
          "   ├─ Timestamp: #{genesis_block.header.timestamp} (July 14, 2025 - Bastille Day)"
        )

        Logger.info("   ├─ Nonce: #{genesis_block.header.nonce} (Year of French Revolution)")
        Logger.info("   ├─ Difficulty: #{genesis_block.header.difficulty} (No mining required)")

        Logger.info(
          "   ├─ Hash: #{Base.encode16(genesis_block.hash, case: :lower) |> String.slice(0, 16)}...#{Base.encode16(genesis_block.hash, case: :lower) |> String.slice(-8, 8)}"
        )

        Logger.info("   └─ Size: #{byte_size(:erlang.term_to_binary(genesis_block))} bytes")
        Logger.info("💰 GENESIS TRANSACTION:")
        Logger.info("   ├─ From: #{genesis_tx.from} (The People)")
        Logger.info("   ├─ To: #{genesis_tx.to} (Revolutionary Address)")
        Logger.info("   ├─ Amount: 1789.0 BAST (#{genesis_tx.amount} juillet)")
        Logger.info("   ├─ Message: \"#{genesis_tx.data}\"")
        Logger.info("   └─ Revolutionary Initial Supply: 1 block reward worth")

        # Save genesis balance to State storage instead of memory
        State.update_balance(genesis_tx.to, genesis_tx.amount)

        initial_state = %__MODULE__{
          blocks: [genesis_block],
          height: 0,
          head_hash: genesis_block.hash
        }

        # Save genesis state to new 4-database architecture
        save_blockchain_to_new_storage(initial_state)

        Chain.store_cumulative_work(
          genesis_block.hash,
          Mining.work_for_difficulty(genesis_block.header.difficulty)
        )

        Logger.info("✅ GENESIS STATE PERSISTED:")
        Logger.info("   ├─ Blocks: Saved to time-partitioned storage")
        Logger.info("   ├─ Chain: Metadata stored in chain.cubdb")
        Logger.info("   ├─ State: Account balances in state.cubdb")
        Logger.info("   └─ Index: Transaction indexes in index.cubdb")
        Logger.info("🚀 Bastille blockchain initialized and ready for revolution!")
        Logger.info("🏰═══════════════════════════════════════════════════════════════")
        {:ok, initial_state}

      {:error, reason} ->
        Logger.error("Failed to load blockchain: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:get_height, _from, %{height: height} = state) do
    {:reply, height, state}
  end

  def handle_call(:get_head_block, _from, %{blocks: [head_block | _]} = state) do
    {:reply, head_block, state}
  end

  def handle_call(:get_head_block, _from, %{blocks: []} = state) do
    {:reply, nil, state}
  end

  def handle_call({:get_block, hash}, _from, state) do
    # Use new block storage to find the block
    case Blocks.get_block(hash) do
      {:ok, block} -> {:reply, block, state}
      {:error, :not_found} -> {:reply, nil, state}
    end
  end

  # get_balance and get_nonce now use State storage directly - no GenServer handlers needed

  def handle_call(:get_all_balances, _from, state) do
    # Get balances directly from State storage instead of memory cache
    balances = State.get_all_balances()
    {:reply, balances, state}
  end

  def handle_call(:get_all_blocks, _from, %{blocks: blocks} = state) do
    {:reply, blocks, state}
  end

  def handle_call(
        {:add_block, %Bastille.Features.Block.Block{} = block},
        _from,
        %__MODULE__{} = state
      ) do
    # First try to add the block directly; fall back to the orphan pool on a height gap.
    case try_add_block_directly(block, state) do
      {:ok, new_state} ->
        updated_state = post_add_success(block, new_state)
        {:reply, :ok, updated_state}

      {:error, :invalid_height} ->
        {:reply, handle_orphan_add(block), state}

      {:error, reason} = error ->
        Logger.error("❌ Block processing failed: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  def handle_call({:reorganize, result}, _from, %__MODULE__{} = state) do
    case do_reorganize(result, state) do
      {:ok, summary, new_state} -> {:reply, {:ok, summary}, new_state}
      # On any failure the original chain has been restored in storage; reply
      # with the unchanged in-memory state.
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  # NOTE: validate_transaction no longer takes a GenServer.call — see the
  # public API doc above. The pure validator lives in
  # `Bastille.Features.Chain.TransactionValidator`.

  def handle_call({:get_transactions_for_address, address}, _from, state) do
    case Index.get_address_transactions(address) do
      {:ok, tx_hashes} ->
        # Convert transaction hashes to actual transactions
        transactions = get_transactions_by_hashes(tx_hashes)
        {:reply, transactions, state}

      _error ->
        {:reply, [], state}
    end
  end

  def handle_call({:get_recent_blocks, count}, _from, %{blocks: blocks} = state) do
    recent = Enum.take(blocks, count)
    {:reply, recent, state}
  end

  def handle_call({:get_recent_block_times, count}, _from, %{blocks: blocks} = state) do
    recent_block_times =
      Enum.take(blocks, count)
      |> Enum.map(fn block -> %{index: block.header.index, timestamp: block.header.timestamp} end)

    {:reply, recent_block_times, state}
  end

  # Private functions for new storage architecture

  defp load_blockchain_from_new_storage do
    case Chain.get_head() do
      {:ok, {height, head_hash}} ->
        # Load recent blocks into memory (last 100 for performance)
        recent_blocks = load_recent_blocks(height)

        # No need to load balances/nonces into memory - use State storage directly
        state = %__MODULE__{
          blocks: recent_blocks,
          height: height,
          head_hash: head_hash
        }

        {:ok, state}

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  defp save_blockchain_to_new_storage(state) do
    # Update chain metadata only - balances/nonces are already saved directly to State storage
    Chain.update_head(state.height, state.head_hash)
  end

  defp load_recent_blocks(current_height) do
    # Load last 100 blocks for memory performance
    start_height = max(0, current_height - 99)

    start_height..current_height
    |> Enum.map(fn height ->
      case Chain.get_block_hash_at_height(height) do
        {:ok, block_hash} ->
          case Blocks.get_block(block_hash) do
            {:ok, block} -> block
            _ -> nil
          end

        _ ->
          nil
      end
    end)
    |> Enum.filter(&(&1 != nil))
    # Most recent first
    |> Enum.reverse()
  end

  # load_all_nonces function removed - nonces now accessed directly from State storage

  defp index_block_transactions(%Bastille.Features.Block.Block{} = block) do
    partition = get_current_partition()

    # Index all transactions in the block
    result =
      block.transactions
      |> Enum.with_index()
      |> Enum.reduce_while(:ok, fn {tx, index}, acc ->
        tx_index = %Index.TransactionIndex{
          tx_hash: tx.hash,
          partition: partition,
          block_hash: block.hash,
          from_address: tx.from,
          to_address: tx.to,
          tx_index: index,
          timestamp: tx.timestamp
        }

        case Index.index_transaction(tx_index) do
          :ok -> {:cont, acc}
          error -> {:halt, error}
        end
      end)

    # Index the block itself if transactions indexing succeeded
    case result do
      :ok -> Index.index_block(block.hash, partition, block.header.timestamp)
      error -> error
    end
  end

  defp post_add_success(%Bastille.Features.Block.Block{} = block, %__MODULE__{} = new_state) do
    # Process orphans depending on this parent
    OrphanManager.process_orphans_for_parent(block.hash)
    |> Enum.each(fn orphan_block ->
      Task.start(fn -> GenServer.call(__MODULE__, {:add_block, orphan_block}) end)
    end)

    purge_block_txs_from_mempool(block)

    # Best-effort broadcast
    try do
      Bastille.Features.P2P.PeerManagement.Node.broadcast_block(block)
      Logger.debug("📡 Block #{block.header.index} broadcasted to P2P network")
    catch
      kind, reason ->
        Logger.warning("⚠️ Failed to broadcast block to P2P: #{kind} #{inspect(reason)}")
    end

    new_state
  end

  # A confirmed block's transactions must leave the mempool on every node that
  # applies it — not only the miner — so they stop showing as pending and can't
  # be re-mined. Coinbase txs are never in the mempool, so most (coinbase-only)
  # blocks skip the mempool call entirely.
  defp purge_block_txs_from_mempool(%Bastille.Features.Block.Block{transactions: txs}) do
    case Enum.reject(txs, &(&1.signature_type == :coinbase)) do
      [] ->
        :ok

      user_txs ->
        user_txs
        |> Enum.map(& &1.hash)
        |> Bastille.Features.Transaction.Mempool.remove_transactions()
    end
  end

  defp handle_orphan_add(%Bastille.Features.Block.Block{} = block) do
    case OrphanManager.add_orphan_block(block) do
      :ok ->
        Logger.info("🔄 Block #{block.header.index} added to orphan pool")
        {:orphan, :added_to_pool}

      {:orphan, parent_hash} ->
        Logger.info(
          "🔄 Block #{block.header.index} stored as orphan (missing parent: #{encode_hash(parent_hash)})"
        )

        {:orphan, parent_hash}

      {:error, reason} = error ->
        Logger.error("❌ Orphan pool rejected block: #{inspect(reason)}")
        error
    end
  end

  defp get_current_partition do
    {{year, month, _day}, _time} = :calendar.universal_time()
    "#{year}#{String.pad_leading("#{month}", 2, "0")}"
  end

  defp get_transactions_by_hashes(_tx_hashes) do
    # This would need to look up transactions from blocks
    # For now, return empty list (can be implemented later)
    []
  end

  # Helper functions for orphan handling

  defp try_add_block_directly(%Bastille.Features.Block.Block{} = block, %__MODULE__{} = state) do
    with :ok <- validate_block(block, state),
         journal <- capture_state_journal(block),
         new_state <- apply_block_to_state(block, state),
         :ok <- Blocks.store_block(block),
         :ok <- Chain.store_block_link(new_state.height, block.hash),
         :ok <- store_cumulative_work(block),
         :ok <- State.store_journal(block.hash, journal),
         :ok <- prune_old_journal(new_state.height),
         :ok <- Chain.update_head(new_state.height, block.hash),
         :ok <- index_block_transactions(block),
         :ok <- save_blockchain_to_new_storage(new_state) do
      Logger.info("✅ Block #{block.header.index} added to blockchain (4-DB architecture)")
      {:ok, new_state}
    else
      {:error, _reason} = error ->
        error
    end
  end

  # Capture the pre-application balance/nonce of every address a block touches,
  # so the block can be rolled back during a reorg.
  defp capture_state_journal(%Block{} = block) do
    block
    |> touched_addresses()
    |> Enum.map(fn address ->
      balance =
        case State.get_balance(address) do
          {:ok, b} -> b
          _ -> 0
        end

      nonce =
        case State.get_nonce(address) do
          {:ok, n} -> n
          _ -> 0
        end

      {address, balance, nonce}
    end)
  end

  defp touched_addresses(%Block{} = block) do
    block.transactions
    |> Enum.flat_map(fn
      %Transaction{signature_type: :coinbase, to: to} -> [to]
      %Transaction{from: "1789Genesis", to: to} -> [to]
      %Transaction{from: from, to: to} -> [from, to]
    end)
    |> Enum.uniq()
  end

  # Drop the journal that falls outside the reorg window (height - @max_reorg_depth).
  defp prune_old_journal(height) when height > @max_reorg_depth do
    case Chain.get_block_hash_at_height(height - @max_reorg_depth) do
      {:ok, old_hash} -> State.delete_journal(old_hash)
      {:error, :not_found} -> :ok
    end
  end

  defp prune_old_journal(_height), do: :ok

  # Persist cumulative_work = parent.cumulative_work + work(this block).
  # A missing parent (e.g. genesis) counts as 0 work.
  defp store_cumulative_work(%Block{} = block) do
    parent_work =
      case Chain.get_cumulative_work(block.header.previous_hash) do
        {:ok, work} -> work
        {:error, :not_found} -> 0
      end

    Chain.store_cumulative_work(
      block.hash,
      parent_work + Mining.work_for_difficulty(block.header.difficulty)
    )
  end

  defp encode_hash(hash) when is_binary(hash) do
    Base.encode16(hash, case: :lower) |> String.slice(0, 12)
  end

  # ── Chain reorganization (Sprint 4.4) ──────────────────────────────────────

  defp do_reorganize(%{better?: false}, _state), do: {:error, :not_better}
  defp do_reorganize(%{fork_chain: []}, _state), do: {:error, :empty_fork}

  defp do_reorganize(
         %{better?: true, ancestor_hash: ancestor_hash, fork_chain: fork_chain},
         %__MODULE__{} = state
       ) do
    case split_at_ancestor(state.blocks, ancestor_hash) do
      :ancestor_not_found ->
        Logger.warning(
          "❌ REORG ABORTED — common ancestor #{encode_hash(ancestor_hash)} is no longer in memory (fork too deep)"
        )

        {:error, :ancestor_not_in_memory}

      {old_blocks, ancestor_tail} ->
        switch_to_fork(state, ancestor_hash, fork_chain, old_blocks, ancestor_tail)
    end
  end

  # Roll the current chain back to the common ancestor, then apply the fork
  # oldest-first under full validation. All-or-nothing: a failed fork block
  # restores the original chain.
  defp switch_to_fork(%__MODULE__{} = state, ancestor_hash, fork_chain, old_blocks, ancestor_tail) do
    ancestor_state = %{
      state
      | blocks: ancestor_tail,
        height: state.height - length(old_blocks),
        head_hash: ancestor_hash
    }

    Enum.each(old_blocks, fn b -> State.rollback_block(b.hash) end)

    case apply_fork(fork_chain, ancestor_state) do
      {:ok, new_state} ->
        finish_reorg(new_state, ancestor_hash, fork_chain, old_blocks)

      {:error, reason, applied_blocks} ->
        recover_original_chain(applied_blocks, old_blocks, ancestor_state)
        log_reorg_aborted(reason, ancestor_hash, length(old_blocks), length(applied_blocks))
        {:error, reason}
    end
  end

  defp finish_reorg(%__MODULE__{} = new_state, ancestor_hash, fork_chain, old_blocks) do
    clear_stale_links(old_blocks, new_state.height)
    reinjected = reinject_orphaned_txs(old_blocks, fork_chain)

    summary = %{
      ancestor_hash: ancestor_hash,
      rolled_back: length(old_blocks),
      applied: length(fork_chain),
      new_height: new_state.height,
      new_head: new_state.head_hash,
      reinjected: reinjected
    }

    log_reorg_success(summary)
    {:ok, summary, new_state}
  end

  # Split the in-memory blocks (newest-first) into the blocks above the ancestor
  # and the tail starting at the ancestor. `:ancestor_not_found` means the fork
  # point fell outside the in-memory window — the reorg is abandoned.
  defp split_at_ancestor(blocks, ancestor_hash) do
    case Enum.split_while(blocks, fn b -> b.hash != ancestor_hash end) do
      {_newer, []} -> :ancestor_not_found
      {newer, tail} -> {newer, tail}
    end
  end

  # Apply fork blocks oldest-first. Returns the final state, or the reason and
  # the (newest-first) list of fork blocks applied before the failure.
  defp apply_fork(fork_chain, ancestor_state) do
    fork_chain
    |> Enum.reduce_while({ancestor_state, []}, fn block, {acc_state, applied} ->
      case try_add_block_directly(block, acc_state) do
        {:ok, new_state} -> {:cont, {new_state, [block | applied]}}
        {:error, reason} -> {:halt, {:error, reason, applied}}
      end
    end)
    |> case do
      {:error, reason, applied} -> {:error, reason, applied}
      {final_state, _applied} -> {:ok, final_state}
    end
  end

  # Undo the fork blocks that did apply (newest-first already), then re-apply the
  # original chain oldest-first so storage and balances return to their pre-reorg
  # state.
  defp recover_original_chain(applied_fork_blocks, old_blocks, ancestor_state) do
    Enum.each(applied_fork_blocks, fn b -> State.rollback_block(b.hash) end)

    old_blocks
    |> Enum.reverse()
    |> Enum.reduce(ancestor_state, fn b, acc ->
      case try_add_block_directly(b, acc) do
        {:ok, new_state} ->
          new_state

        {:error, reason} ->
          Logger.error(
            "🔥 REORG RECOVERY could not re-apply block #{b.header.index}: #{inspect(reason)}"
          )

          acc
      end
    end)
  end

  # When the winning fork is shorter than the chain it replaced, the height→hash
  # links above the new head still point at the discarded blocks. Drop them.
  defp clear_stale_links(old_blocks, new_height) do
    old_blocks
    |> Enum.filter(fn b -> b.header.index > new_height end)
    |> Enum.each(fn b -> Chain.delete_block_link(b.header.index, b.hash) end)
  end

  # Re-inject transactions from the orphaned blocks into the mempool, skipping
  # coinbases and any tx already present in the fork, and only if they still
  # validate against the new chain state. Best-effort — never fails the reorg.
  defp reinject_orphaned_txs(old_blocks, fork_chain) do
    fork_tx_hashes =
      fork_chain |> Enum.flat_map(& &1.transactions) |> MapSet.new(& &1.hash)

    old_blocks
    |> Enum.flat_map(& &1.transactions)
    |> Enum.reject(fn tx -> coinbase_tx?(tx) or MapSet.member?(fork_tx_hashes, tx.hash) end)
    |> Enum.reduce(0, fn tx, count ->
      with :ok <- TransactionValidator.validate(tx),
           :ok <- safe_add_to_mempool(tx) do
        count + 1
      else
        _ -> count
      end
    end)
  end

  defp safe_add_to_mempool(tx) do
    Bastille.Features.Transaction.Mempool.add_transaction(tx)
  catch
    kind, reason ->
      Logger.warning("⚠️ Could not re-inject tx into mempool: #{kind} #{inspect(reason)}")
      :error
  end

  defp coinbase_tx?(%Transaction{signature_type: :coinbase}), do: true
  defp coinbase_tx?(%Transaction{from: "1789Genesis"}), do: true
  defp coinbase_tx?(_), do: false

  defp log_reorg_success(summary) do
    Logger.info("🔄 ═══════════════ REORG SUCCESS ═══════════════")
    Logger.info("   ├─ ancestor:       #{encode_hash(summary.ancestor_hash)}")
    Logger.info("   ├─ rolled_back:    #{summary.rolled_back} block(s)")
    Logger.info("   ├─ applied:        #{summary.applied} block(s)")
    Logger.info("   ├─ new_height:     #{summary.new_height}")
    Logger.info("   ├─ new_head:       #{encode_hash(summary.new_head)}")
    Logger.info("   └─ txs_reinjected: #{summary.reinjected}")
  end

  defp log_reorg_aborted(reason, ancestor_hash, rolled_back, applied) do
    Logger.warning("❌ ═══════════════ REORG ABORTED ═══════════════")
    Logger.warning("   ├─ reason:       #{inspect(reason)}")
    Logger.warning("   ├─ ancestor:     #{encode_hash(ancestor_hash)}")
    Logger.warning("   ├─ rolled_back:  #{rolled_back} block(s) (restored)")
    Logger.warning("   └─ applied:      #{applied} fork block(s) (reverted)")
  end

  # Existing validation and state-application logic

  defp validate_block(%Bastille.Features.Block.Block{} = block, %__MODULE__{} = state) do
    cond do
      block.header.index != state.height + 1 ->
        {:error, :invalid_height}

      not validate_block_structure(block) ->
        {:error, :invalid_structure}

      not validate_block_hash(block) ->
        {:error, :invalid_hash}

      not validate_merkle_root(block) ->
        {:error, :invalid_merkle_root}

      not validate_consensus(block) ->
        {:error, :invalid_consensus}

      not validate_all_transactions(block.transactions, state) ->
        {:error, :invalid_transactions}

      true ->
        :ok
    end
  end

  defp validate_block_structure(%Bastille.Features.Block.Block{header: header, transactions: txs}) do
    is_map(header) &&
      is_list(txs) &&
      is_integer(header.index) &&
      is_binary(header.previous_hash) &&
      is_binary(header.merkle_root) &&
      is_integer(header.timestamp) &&
      is_integer(header.nonce) &&
      is_integer(header.difficulty)
  end

  defp validate_block_hash(%Bastille.Features.Block.Block{} = block) do
    # Use validation from the Block module
    case Block.valid_hash?(block) do
      true ->
        true

      false ->
        Logger.warning("❌ Block hash validation failed for block #{block.header.index}")
        false
    end
  end

  defp validate_merkle_root(%Bastille.Features.Block.Block{} = block) do
    # Compute and compare the merkle root
    expected_block = Block.calculate_merkle_root(block)
    valid = expected_block.header.merkle_root == block.header.merkle_root

    unless valid do
      Logger.warning("❌ Merkle root mismatch for block #{block.header.index}")

      Logger.debug(
        "   Expected: #{Base.encode16(expected_block.header.merkle_root, case: :lower) |> String.slice(0, 16)}..."
      )

      Logger.debug(
        "   Received: #{Base.encode16(block.header.merkle_root, case: :lower) |> String.slice(0, 16)}..."
      )
    end

    valid
  end

  defp validate_consensus(block) do
    try do
      consensus_result = Consensus.Engine.validate_block(block)
      Logger.debug("🔍 Consensus validation result: #{inspect(consensus_result)}")

      case consensus_result do
        :ok -> true
        {:ok, _} -> true
        _ -> false
      end
    rescue
      error ->
        Logger.error(
          "🔗 Consensus validation failed for block #{block.header.index}: #{inspect(error)}"
        )

        false
    end
  end

  # Block-level transaction validation reuses the pure validator so that the
  # rules stay in one place (TransactionValidator).
  defp validate_all_transactions(transactions, %__MODULE__{} = _state)
       when is_list(transactions) do
    Enum.all?(transactions, fn tx ->
      TransactionValidator.validate(tx) == :ok
    end)
  end

  # Apply transaction with pattern matching
  defp apply_transaction_to_state(
         %Bastille.Features.Transaction.Transaction{signature_type: :coinbase} = tx,
         state
       ),
       do: apply_coinbase_transaction(tx, state)

  defp apply_transaction_to_state(
         %Bastille.Features.Transaction.Transaction{from: "1789Genesis"} = tx,
         state
       ),
       do: apply_coinbase_transaction(tx, state)

  defp apply_transaction_to_state(
         %Bastille.Features.Transaction.Transaction{} = tx,
         %__MODULE__{} = state
       ) do
    total_cost = tx.amount + tx.fee

    # Get current balances from State storage
    from_balance =
      case State.get_balance(tx.from) do
        {:ok, balance} -> balance
        {:error, :not_found} -> 0
      end

    to_balance =
      case State.get_balance(tx.to) do
        {:ok, balance} -> balance
        {:error, :not_found} -> 0
      end

    # Update balances and nonce in State storage
    State.update_balance(tx.from, from_balance - total_cost)
    State.update_balance(tx.to, to_balance + tx.amount)
    State.update_nonce(tx.from, tx.nonce)

    # Return state unchanged (no in-memory balance/nonce tracking)
    state
  end

  # Apply transaction with block context (needed for coinbase transactions)
  defp apply_transaction_to_state_with_block(
         %Bastille.Features.Transaction.Transaction{signature_type: :coinbase} = tx,
         block,
         state
       ),
       do: apply_coinbase_transaction_with_block(tx, block, state)

  defp apply_transaction_to_state_with_block(
         %Bastille.Features.Transaction.Transaction{from: "1789Genesis"} = tx,
         block,
         state
       ),
       do: apply_coinbase_transaction_with_block(tx, block, state)

  defp apply_transaction_to_state_with_block(tx, _block, state),
    do: apply_transaction_to_state(tx, state)

  defp apply_coinbase_transaction(
         %Bastille.Features.Transaction.Transaction{} = tx,
         %__MODULE__{} = state
       ) do
    current_balance =
      case State.get_balance(tx.to) do
        {:ok, balance} -> balance
        {:error, :not_found} -> 0
      end

    State.update_balance(tx.to, current_balance + tx.amount)
    state
  end

  # Block-context variant is kept for symmetry with apply_transaction_to_state_with_block/3
  # but currently behaves the same as the no-context variant. The block hash will be needed
  # again when chain reorganization is implemented (to journal state changes per block).
  defp apply_coinbase_transaction_with_block(
         %Bastille.Features.Transaction.Transaction{} = tx,
         _block,
         %__MODULE__{} = state
       ) do
    apply_coinbase_transaction(tx, state)
  end

  defp apply_block_to_state(%Bastille.Features.Block.Block{} = block, %__MODULE__{} = state) do
    # Apply all transactions in the block with block context
    new_state =
      Enum.reduce(block.transactions, state, fn tx, acc_state ->
        apply_transaction_to_state_with_block(tx, block, acc_state)
      end)

    # Note: maturity processing is performed by try_add_block_directly/2 AFTER
    # the block is persisted, so that block_still_in_chain? can locate the
    # just-mined block in Blocks storage.

    # Update blockchain state
    %{
      new_state
      | blocks: [block | new_state.blocks],
        height: new_state.height + 1,
        head_hash: block.hash
    }
  end
end
