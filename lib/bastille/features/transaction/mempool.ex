defmodule Bastille.Features.Transaction.Mempool do
  @moduledoc """
  Transaction Mempool — simple and robust like Bitcoin.

  Manages only pending transactions awaiting inclusion in a block.
  Bitcoin principle: One responsibility = One module.
  """

  use GenServer
  require Logger

  alias Bastille.Features.Chain.Chain
  alias Bastille.Features.Transaction.Transaction

  # Default configuration (Bitcoin-inspired values)
  @default_max_size 4000        # Max transactions in memory
  @default_min_fee 1000         # Minimum fee in juillet units
  @cleanup_interval_ms 300_000  # Cleanup every 5 minutes

  defstruct [
    transactions: :gb_trees.empty(),  # Priority-ordered tree
    tx_by_hash: %{},                  # Fast index by hash
    max_size: @default_max_size,
    min_fee: @default_min_fee,
    skip_signature_validation: false, # TEST ONLY: bypass signature validation
    skip_chain_validation: false      # TEST ONLY: bypass chain validation
  ]

  @type t :: %__MODULE__{
    transactions: :gb_trees.tree(priority :: {non_neg_integer(), integer(), binary()}, Transaction.t()),
    tx_by_hash: %{binary() => Transaction.t()},
    max_size: pos_integer(),
    min_fee: non_neg_integer(),
    skip_signature_validation: boolean(),
    skip_chain_validation: boolean()
  }

  # Client API

  @doc "Start the mempool"
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Add a transaction to the mempool"
  @spec add_transaction(Transaction.t()) :: :ok | {:error, term()}
  def add_transaction(%Transaction{} = tx) do
    GenServer.call(__MODULE__, {:add_transaction, tx})
  end

  @doc "Fetch best transactions for a block"
  @spec get_transactions(pos_integer()) :: [Transaction.t()]
  def get_transactions(limit \\ 100) do
    GenServer.call(__MODULE__, {:get_transactions, limit})
  end

  @doc "Remove transactions from the mempool (after block inclusion)"
  @spec remove_transactions([binary()]) :: :ok
  def remove_transactions(tx_hashes) when is_list(tx_hashes) do
    GenServer.call(__MODULE__, {:remove_transactions, tx_hashes})
  end

  @doc "Get a transaction by its hash"
  @spec get_transaction(binary()) :: Transaction.t() | nil
  def get_transaction(tx_hash) do
    GenServer.call(__MODULE__, {:get_transaction, tx_hash})
  end

  @doc "All transactions in the mempool"
  @spec all_transactions() :: [Transaction.t()]
  def all_transactions do
    GenServer.call(__MODULE__, :all_transactions)
  end

  @doc "Current mempool size"
  @spec size() :: non_neg_integer()
  def size do
    GenServer.call(__MODULE__, :size)
  end

  @doc "Clear the mempool (for tests)"
  @spec clear() :: :ok
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  # GenServer Implementation

  @impl true
  def init(opts) do
    max_size = Keyword.get(opts, :max_size, @default_max_size)
    min_fee = Keyword.get(opts, :min_fee, @default_min_fee)
    skip_signature_validation = Keyword.get(opts, :skip_signature_validation, false)
    skip_chain_validation = Keyword.get(opts, :skip_chain_validation, false)

    state = %__MODULE__{
      transactions: :gb_trees.empty(),
      tx_by_hash: %{},
      max_size: max_size,
      min_fee: min_fee,
      skip_signature_validation: skip_signature_validation,
      skip_chain_validation: skip_chain_validation
    }

    # Periodic cleanup like Bitcoin
    Process.send_after(self(), :cleanup_stale, @cleanup_interval_ms)

    Logger.info("🔄 Transaction Mempool started (Bitcoin-style)")
    Logger.info("   └─ Max size: #{max_size}, Min fee: #{min_fee} juillet")

    {:ok, state}
  end

  @impl true
  def handle_call({:add_transaction, %Transaction{} = tx}, _from, %__MODULE__{} = state) do
    case validate_and_add_transaction(tx, state) do
      {:ok, new_state} ->
        Logger.debug("📝 Transaction #{encode_hash(tx.hash)} added to mempool")
        {:reply, :ok, new_state}

      {:error, reason} = error ->
        Logger.debug("⚠️ Transaction rejected: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:get_transactions, limit}, _from, %__MODULE__{} = state) do
    # Fetch transactions with highest priority
    transactions =
      state.transactions
      |> :gb_trees.to_list()
      |> Enum.sort_by(fn {{fee, _neg_timestamp, _hash}, _tx} -> fee end, :desc)
      |> Enum.take(limit)
      |> Enum.map(fn {_priority, tx} -> tx end)

    {:reply, transactions, state}
  end

  @impl true
  def handle_call({:remove_transactions, tx_hashes}, _from, %__MODULE__{} = state) do
    new_state = remove_transactions_from_state(tx_hashes, state)
    Logger.debug("🗑️ Removed #{length(tx_hashes)} transactions from mempool")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:get_transaction, tx_hash}, _from, %__MODULE__{} = state) do
    transaction = Map.get(state.tx_by_hash, tx_hash)
    {:reply, transaction, state}
  end

  @impl true
  def handle_call(:all_transactions, _from, %__MODULE__{} = state) do
    transactions = Map.values(state.tx_by_hash)
    {:reply, transactions, state}
  end

  @impl true
  def handle_call(:size, _from, %__MODULE__{} = state) do
    size = map_size(state.tx_by_hash)
    {:reply, size, state}
  end

  @impl true
  def handle_call(:clear, _from, %__MODULE__{} = state) do
    new_state = %{state |
      transactions: :gb_trees.empty(),
      tx_by_hash: %{}
    }
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:cleanup_stale, %__MODULE__{} = state) do
    new_state = cleanup_stale_transactions(state)

    # Schedule next cleanup
    Process.send_after(self(), :cleanup_stale, @cleanup_interval_ms)

    {:noreply, new_state}
  end

  # Private functions

  defp validate_and_add_transaction(%Transaction{} = tx, %__MODULE__{} = state) do
    with :ok <- validate_transaction_structure(tx, state),
         :ok <- validate_transaction_fee(tx, state),
         :ok <- validate_transaction_against_chain(tx, state),
         :ok <- check_mempool_capacity(state),
         false <- transaction_exists?(tx, state) do
      {:ok, add_transaction_to_state(tx, state)}
    else
      true -> {:error, :already_exists}
      error -> error
    end
  end

  # TEST ONLY: Validation that bypasses signatures when skip_signature_validation is true
  defp validate_transaction_structure(%Transaction{} = tx, %__MODULE__{skip_signature_validation: true}) do
    if Transaction.valid_for_testing?(tx) do
      :ok
    else
      {:error, :invalid_structure}
    end
  end
  defp validate_transaction_structure(%Transaction{} = tx, _state) do
    validate_transaction_structure(tx)
  end

  defp validate_transaction_structure(%Transaction{} = tx) do
    if Transaction.valid?(tx) do
      :ok
    else
      {:error, :invalid_structure}
    end
  end

  defp validate_transaction_fee(%Transaction{fee: fee}, %__MODULE__{min_fee: min_fee}) do
    if fee >= min_fee do
      :ok
    else
      {:error, :insufficient_fee}
    end
  end

  defp validate_transaction_against_chain(%Transaction{} = tx) do
    Chain.validate_transaction(tx)
  end

  # TEST ONLY: Skip chain validation when skip_chain_validation is true
  defp validate_transaction_against_chain(%Transaction{}, %__MODULE__{skip_chain_validation: true}) do
    :ok
  end
  defp validate_transaction_against_chain(%Transaction{} = tx, _state) do
    validate_transaction_against_chain(tx)
  end

  defp check_mempool_capacity(%__MODULE__{tx_by_hash: tx_by_hash, max_size: max_size}) do
    if map_size(tx_by_hash) < max_size do
      :ok
    else
      {:error, :mempool_full}
    end
  end

  defp transaction_exists?(%Transaction{hash: hash}, %__MODULE__{tx_by_hash: tx_by_hash}) do
    Map.has_key?(tx_by_hash, hash)
  end

  defp add_transaction_to_state(%Transaction{} = tx, %__MODULE__{} = state) do
    priority = calculate_priority(tx)

    new_transactions = :gb_trees.enter(priority, tx, state.transactions)
    new_tx_by_hash = Map.put(state.tx_by_hash, tx.hash, tx)

    %{state |
      transactions: new_transactions,
      tx_by_hash: new_tx_by_hash
    }
  end

  defp calculate_priority(%Transaction{fee: fee, timestamp: timestamp, hash: hash}) do
    # Priority = fee (higher is better) + negative timestamp (older is better) + hash for uniqueness
    # Hash ensures no two transactions have exactly the same priority
    {fee, -timestamp, hash}
  end

  defp remove_transactions_from_state(tx_hashes, %__MODULE__{} = state) do
    # Remove from tx_by_hash
    new_tx_by_hash = Map.drop(state.tx_by_hash, tx_hashes)

    # Remove from priority tree
    new_transactions =
      :gb_trees.to_list(state.transactions)
      |> Enum.reject(fn {_priority, tx} -> tx.hash in tx_hashes end)
      |> Enum.reduce(:gb_trees.empty(), fn {priority, tx}, acc ->
        :gb_trees.enter(priority, tx, acc)
      end)

    %{state |
      transactions: new_transactions,
      tx_by_hash: new_tx_by_hash
    }
  end

  defp cleanup_stale_transactions(%__MODULE__{} = state) do
    # Remove too-old transactions (> 24h)
    now = System.system_time(:second)
    cutoff = now - 86_400  # 24 hours

    stale_hashes =
      state.tx_by_hash
      |> Enum.filter(fn {_hash, tx} -> tx.timestamp < cutoff end)
      |> Enum.map(fn {hash, _tx} -> hash end)

    if length(stale_hashes) > 0 do
      Logger.info("🧹 Cleaning #{length(stale_hashes)} stale transactions from mempool")
      remove_transactions_from_state(stale_hashes, state)
    else
      state
    end
  end

  defp encode_hash(hash) when is_binary(hash) do
    hash |> Base.encode16() |> String.slice(0, 8)
  end
end
