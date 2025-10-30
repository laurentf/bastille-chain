defmodule Bastille.Infrastructure.Storage.CubDB.Chain do
  @moduledoc """
  Chain structure and metadata storage (chain.cubdb).

  RocksDB-Compatible Design:
  - Namespaced keys (like column families)
  - Consistent serialization format
  - Atomic batch operations
  - Range/prefix queries

  Stores:
  - Block heights → block hashes
  - Chain metadata (current height, head hash)
  - Difficulty adjustments
  - Chain links (parent → child relationships)
  """

  use GenServer
  require Logger
  alias Bastille.Infrastructure.Storage.CubDB.Batch

  defstruct [:chain_db, :db_path]

  # Key namespaces (RocksDB column family simulation)
  @height_to_hash_prefix "h2h:"     # "h2h:00001234" → block_hash
  @hash_to_height_prefix "hash2h:"  # "hash2h:ABCD..." → height
  @metadata_prefix "meta:"          # "meta:height", "meta:head_hash"
  @difficulty_prefix "diff:"        # "diff:00001234" → difficulty
  @parent_child_prefix "pc:"        # "pc:parent_hash" → [child_hashes]

  @doc """
  Start the chain metadata storage.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Store block in chain (height → hash mapping).
  """
  @spec store_block_link(non_neg_integer(), binary()) :: :ok | {:error, term()}
  def store_block_link(height, block_hash) do
    GenServer.call(__MODULE__, {:store_block_link, height, block_hash})
  end

  @doc """
  Get block hash at specific height.
  """
  @spec get_block_hash_at_height(non_neg_integer()) :: {:ok, binary()} | {:error, :not_found}
  def get_block_hash_at_height(height) do
    GenServer.call(__MODULE__, {:get_block_hash_at_height, height})
  end

  @doc """
  Get height of a block hash.
  """
  @spec get_height_of_hash(binary()) :: {:ok, non_neg_integer()} | {:error, :not_found}
  def get_height_of_hash(block_hash) do
    GenServer.call(__MODULE__, {:get_height_of_hash, block_hash})
  end

  @doc """
  Update current chain head.
  """
  @spec update_head(non_neg_integer(), binary()) :: :ok | {:error, term()}
  def update_head(height, head_hash) do
    GenServer.call(__MODULE__, {:update_head, height, head_hash})
  end

  @doc """
  Get current chain head.
  """
  @spec get_head() :: {:ok, {non_neg_integer(), binary()}} | {:error, :not_found}
  def get_head do
    GenServer.call(__MODULE__, :get_head)
  end

  @doc """
  Store difficulty for a block height.
  """
  @spec store_difficulty(non_neg_integer(), float()) :: :ok | {:error, term()}
  def store_difficulty(height, difficulty) do
    GenServer.call(__MODULE__, {:store_difficulty, height, difficulty})
  end

  @doc """
  Get difficulty at specific height.
  """
  @spec get_difficulty_at_height(non_neg_integer()) :: {:ok, float()} | {:error, :not_found}
  def get_difficulty_at_height(height) do
    GenServer.call(__MODULE__, {:get_difficulty_at_height, height})
  end

  @doc """
  Store parent-child relationship.
  """
  @spec store_parent_child_link(binary(), binary()) :: :ok | {:error, term()}
  def store_parent_child_link(parent_hash, child_hash) do
    GenServer.call(__MODULE__, {:store_parent_child_link, parent_hash, child_hash})
  end

  @doc """
  Get chain statistics.
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  # GenServer Callbacks

  @impl true
  def init(opts) do
    db_path = Keyword.get(opts, :db_path, Bastille.Infrastructure.Storage.CubDB.Paths.chain_path())
    File.mkdir_p!(Path.dirname(db_path))

    {:ok, chain_db} = CubDB.start_link(data_dir: db_path)

    state = %__MODULE__{
      chain_db: chain_db,
      db_path: db_path
    }

    Logger.info("🔗 Chain storage initialized at #{db_path}")
    {:ok, state}
  end

  @impl true
  def handle_call({:store_block_link, height, block_hash}, _from, state) do
    height_key = @height_to_hash_prefix <> height_to_key(height)
    hash_key = @hash_to_height_prefix <> Base.encode16(block_hash)

    # Atomic batch operation (RocksDB-compatible)
    operations = [
      {:put, height_key, block_hash},
      {:put, hash_key, height}
    ]

    case batch_write(state.chain_db, operations) do
      :ok -> {:reply, :ok, state}
      error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:get_block_hash_at_height, height}, _from, state) do
    key = @height_to_hash_prefix <> height_to_key(height)

    case CubDB.get(state.chain_db, key) do
      nil -> {:reply, {:error, :not_found}, state}
      block_hash -> {:reply, {:ok, block_hash}, state}
    end
  end

  @impl true
  def handle_call({:get_height_of_hash, block_hash}, _from, state) do
    key = @hash_to_height_prefix <> Base.encode16(block_hash)

    case CubDB.get(state.chain_db, key) do
      nil -> {:reply, {:error, :not_found}, state}
      height -> {:reply, {:ok, height}, state}
    end
  end

  @impl true
  def handle_call({:update_head, height, head_hash}, _from, state) do
    operations = [
      {:put, @metadata_prefix <> "height", height},
      {:put, @metadata_prefix <> "head_hash", head_hash}
    ]

    case batch_write(state.chain_db, operations) do
      :ok -> {:reply, :ok, state}
      error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:get_head, _from, state) do
    height_key = @metadata_prefix <> "height"
    hash_key = @metadata_prefix <> "head_hash"

    case {CubDB.get(state.chain_db, height_key), CubDB.get(state.chain_db, hash_key)} do
      {nil, _} -> {:reply, {:error, :not_found}, state}
      {_, nil} -> {:reply, {:error, :not_found}, state}
      {height, head_hash} -> {:reply, {:ok, {height, head_hash}}, state}
    end
  end

  @impl true
  def handle_call({:store_difficulty, height, difficulty}, _from, state) do
    key = @difficulty_prefix <> height_to_key(height)

    case CubDB.put(state.chain_db, key, difficulty) do
      :ok -> {:reply, :ok, state}
      error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:get_difficulty_at_height, height}, _from, state) do
    key = @difficulty_prefix <> height_to_key(height)

    case CubDB.get(state.chain_db, key) do
      nil -> {:reply, {:error, :not_found}, state}
      difficulty -> {:reply, {:ok, difficulty}, state}
    end
  end

  @impl true
  def handle_call({:store_parent_child_link, parent_hash, child_hash}, _from, state) do
    key = @parent_child_prefix <> Base.encode16(parent_hash)

    # Get existing children, add new child
    existing_children = CubDB.get(state.chain_db, key) || []
    updated_children = [child_hash | existing_children] |> Enum.uniq()

    case CubDB.put(state.chain_db, key, updated_children) do
      :ok -> {:reply, :ok, state}
      error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    # Count entries by prefix (RocksDB-compatible range queries)
    height_count = count_keys_with_prefix(state.chain_db, @height_to_hash_prefix)

    stats = %{
      total_blocks_indexed: height_count,
      storage_type: "chain_metadata",
      db_path: state.db_path,
      namespaces: %{
        height_to_hash: @height_to_hash_prefix,
        hash_to_height: @hash_to_height_prefix,
        metadata: @metadata_prefix,
        difficulty: @difficulty_prefix,
        parent_child: @parent_child_prefix
      }
    }

    {:reply, stats, state}
  end

  # Private functions

  defp height_to_key(height) do
    # Zero-padded height for proper sorting (RocksDB lexicographic order)
    String.pad_leading("#{height}", 10, "0")
  end

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
