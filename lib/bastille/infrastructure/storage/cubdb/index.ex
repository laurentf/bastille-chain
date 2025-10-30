defmodule Bastille.Infrastructure.Storage.CubDB.Index do
  @moduledoc """
  Index storage for fast lookups (index.cubdb).

  RocksDB-Compatible Design:
  - Namespaced indexes for different lookup types
  - Secondary indexes for efficient queries
  - Range scans for transaction history
  - Bloom filters compatible structure

  Indexes:
  - Transaction hash → block location: "tx:ABCD..." → {partition, block_hash, tx_index}
  - Address → transaction list: "addr:1789ABC..." → [tx_hash1, tx_hash2, ...]
  - Block hash → partition: "bhash:ABCD..." → "202501"
  - Time-based indexes: "time:1641234567" → [block_hashes]
  """

  use GenServer
  require Logger
  alias Bastille.Infrastructure.Storage.CubDB.Batch

  defstruct [:index_db, :db_path]

  # Transaction index structure for better parameter organization
  defmodule TransactionIndex do
    @moduledoc """
    Structure for organizing transaction indexing parameters.

    Groups related transaction metadata for cleaner function signatures.
    """

    @type t :: %__MODULE__{
      tx_hash: binary(),
      partition: String.t(),
      block_hash: binary(),
      from_address: String.t(),
      to_address: String.t(),
      tx_index: non_neg_integer(),
      timestamp: integer()
    }

    defstruct [
      :tx_hash,
      :partition,
      :block_hash,
      :from_address,
      :to_address,
      :tx_index,
      :timestamp
    ]
  end

  # Key namespaces (RocksDB column family simulation)
  @tx_location_prefix "tx:"        # "tx:ABCD..." → {partition, block_hash, index}
  @address_txs_prefix "addr:"      # "addr:1789ABC..." → [tx_hashes]
  @block_partition_prefix "bhash:" # "bhash:ABCD..." → partition
  @time_blocks_prefix "time:"      # "time:1641234567" → [block_hashes]

  @doc """
  Start the index storage.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Index a transaction for fast lookups.

  Accepts a %TransactionIndex{} struct with transaction details for better maintainability.

  ## Examples

      iex> tx_index = %Bastille.Infrastructure.Storage.CubDB.Index.TransactionIndex{
      ...>   tx_hash: <<1, 2, 3>>,
      ...>   partition: "202501",
      ...>   block_hash: <<4, 5, 6>>,
      ...>   from_address: "f789abc...",
      ...>   to_address: "f789def...",
      ...>   tx_index: 0,
      ...>   timestamp: 1640995200
      ...> }
      iex> Bastille.Infrastructure.Storage.CubDB.Index.index_transaction(tx_index)
      :ok
  """
  @spec index_transaction(TransactionIndex.t()) :: :ok
  def index_transaction(%TransactionIndex{} = tx_index_struct) do
    GenServer.call(__MODULE__, {:index_transaction, tx_index_struct})
  end

  @doc """
  Find transaction location by hash.
  """
  @spec find_transaction(binary()) :: {:ok, {String.t(), binary(), non_neg_integer()}} | {:error, :not_found}
  def find_transaction(tx_hash) do
    GenServer.call(__MODULE__, {:find_transaction, tx_hash})
  end

  @doc """
  Get all transactions for an address.
  """
  @spec get_address_transactions(String.t()) :: {:ok, [binary()]}
  def get_address_transactions(address) do
    GenServer.call(__MODULE__, {:get_address_transactions, address})
  end

  @doc """
  Find which partition contains a block.
  """
  @spec find_block_partition(binary()) :: {:ok, String.t()} | {:error, :not_found}
  def find_block_partition(block_hash) do
    GenServer.call(__MODULE__, {:find_block_partition, block_hash})
  end

  @doc """
  Index a block for partition lookup.
  """
  @spec index_block(binary(), String.t(), integer()) :: :ok
  def index_block(block_hash, partition, timestamp) do
    GenServer.call(__MODULE__, {:index_block, block_hash, partition, timestamp})
  end

  @doc """
  Get blocks created around a specific time.
  """
  @spec get_blocks_by_time_range(integer(), integer()) :: {:ok, [binary()]}
  def get_blocks_by_time_range(start_time, end_time) do
    GenServer.call(__MODULE__, {:get_blocks_by_time_range, start_time, end_time})
  end

  @doc """
  Get index statistics.
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  # GenServer Callbacks

  @impl true
  def init(opts) do
    db_path = Keyword.get(opts, :db_path, Bastille.Infrastructure.Storage.CubDB.Paths.index_path())
    File.mkdir_p!(Path.dirname(db_path))

    {:ok, index_db} = CubDB.start_link(data_dir: db_path)

    state = %__MODULE__{
      index_db: index_db,
      db_path: db_path
    }

    Logger.info("📇 Index storage initialized at #{db_path}")
    {:ok, state}
  end

  @impl true
  def handle_call({:index_transaction, %TransactionIndex{} = tx_idx}, _from, state) do
    tx_location = {tx_idx.partition, tx_idx.block_hash, tx_idx.tx_index}

    # Atomic batch operation to update all indexes
    operations = [
      # Transaction location index
      {:put, @tx_location_prefix <> Base.encode16(tx_idx.tx_hash), tx_location},

      # Block partition index
      {:put, @block_partition_prefix <> Base.encode16(tx_idx.block_hash), tx_idx.partition},

      # Time-based block index
      {:put, @time_blocks_prefix <> timestamp_to_key(tx_idx.timestamp), tx_idx.block_hash}
    ]

    # Add address indexes (both from and to)
    operations = operations ++
      add_to_address_index(state.index_db, tx_idx.from_address, tx_idx.tx_hash) ++
      add_to_address_index(state.index_db, tx_idx.to_address, tx_idx.tx_hash)

    case batch_write(state.index_db, operations) do
      :ok ->
        Logger.debug("📇 Indexed transaction: #{Base.encode16(tx_idx.tx_hash, case: :lower) |> String.slice(0, 16)}...")
        {:reply, :ok, state}
      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:find_transaction, tx_hash}, _from, state) do
    key = @tx_location_prefix <> Base.encode16(tx_hash)

    case CubDB.get(state.index_db, key) do
      nil -> {:reply, {:error, :not_found}, state}
      location -> {:reply, {:ok, location}, state}
    end
  end

  @impl true
  def handle_call({:get_address_transactions, address}, _from, state) do
    key = @address_txs_prefix <> address

    case CubDB.get(state.index_db, key) do
      nil -> {:reply, {:ok, []}, state}
      tx_hashes -> {:reply, {:ok, tx_hashes}, state}
    end
  end

  @impl true
  def handle_call({:find_block_partition, block_hash}, _from, state) do
    key = @block_partition_prefix <> Base.encode16(block_hash)

    case CubDB.get(state.index_db, key) do
      nil -> {:reply, {:error, :not_found}, state}
      partition -> {:reply, {:ok, partition}, state}
    end
  end

  @impl true
  def handle_call({:index_block, block_hash, partition, timestamp}, _from, state) do
    operations = [
      {:put, @block_partition_prefix <> Base.encode16(block_hash), partition},
      {:put, @time_blocks_prefix <> timestamp_to_key(timestamp), block_hash}
    ]

    case batch_write(state.index_db, operations) do
      :ok -> {:reply, :ok, state}
      error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:get_blocks_by_time_range, start_time, end_time}, _from, state) do
    start_key = @time_blocks_prefix <> timestamp_to_key(start_time)
    end_key = @time_blocks_prefix <> timestamp_to_key(end_time)

    blocks = CubDB.select(state.index_db, min_key: start_key, max_key: end_key)
    |> Enum.map(fn {_key, block_hash} -> block_hash end)

    {:reply, {:ok, blocks}, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    tx_count = count_keys_with_prefix(state.index_db, @tx_location_prefix)
    block_count = count_keys_with_prefix(state.index_db, @block_partition_prefix)
    address_count = count_keys_with_prefix(state.index_db, @address_txs_prefix)

    stats = %{
      indexed_transactions: tx_count,
      indexed_blocks: block_count,
      indexed_addresses: address_count,
      storage_type: "fast_lookups",
      db_path: state.db_path,
      namespaces: %{
        transaction_location: @tx_location_prefix,
        address_transactions: @address_txs_prefix,
        block_partition: @block_partition_prefix,
        time_blocks: @time_blocks_prefix
      }
    }

    {:reply, stats, state}
  end

  # Private functions

  defp timestamp_to_key(timestamp) do
    # Zero-padded timestamp for proper sorting
    String.pad_leading("#{timestamp}", 15, "0")
  end

  defp add_to_address_index(db, address, tx_hash) do
    return_empty_if_genesis(address, fn ->
      key = @address_txs_prefix <> address
      existing_txs = CubDB.get(db, key) || []
      updated_txs = [tx_hash | existing_txs] |> Enum.uniq() |> Enum.take(1000) # Limit to 1000 recent txs

      [{:put, key, updated_txs}]
    end)
  end

  defp return_empty_if_genesis("1789Genesis", _fun), do: []
  defp return_empty_if_genesis(_address, fun), do: fun.()

  defp batch_write(db, operations) do
    Batch.write(db, operations)
  end

  defp count_keys_with_prefix(db, prefix) do
    CubDB.select(db, min_key: prefix, max_key: prefix <> "\xFF")
    |> Enum.count()
  rescue
    _ -> 0
  end
end
