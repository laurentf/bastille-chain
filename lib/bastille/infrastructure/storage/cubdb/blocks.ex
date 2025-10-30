defmodule Bastille.Infrastructure.Storage.CubDB.Blocks do
  @moduledoc """
  Time-partitioned block storage - creates monthly partition files.

  Partitioning strategy:
  - blocks202501.cubdb (January 2025)
  - blocks202502.cubdb (February 2025)
  - etc.

  Benefits:
  - Smaller files for better performance
  - Easy archival of old months
  - Parallel operations on different partitions
  """

  use GenServer
  require Logger

  alias Bastille.Features.Block.Block
  alias Bastille.Infrastructure.Storage.CubDB.Index

  defstruct [
    :blocks_dbs,          # Map of "YYYYMM" -> CubDB PID
    :current_blocks_db,   # Current month's block database PID
    :current_partition,   # Current partition name (e.g., "202501")
    :db_path              # Base path for databases
  ]

  @doc """
  Start the time-partitioned blocks storage.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Store a block in the appropriate time partition.
  """
  @spec store_block(Block.t()) :: :ok | {:error, term()}
  def store_block(%Bastille.Features.Block.Block{} = block) do
    GenServer.call(__MODULE__, {:store_block, block})
  end

  @doc """
  Get a block by hash (uses index for fast partition lookup).
  """
  @spec get_block(binary()) :: {:ok, Block.t()} | {:error, :not_found}
  def get_block(block_hash) do
    GenServer.call(__MODULE__, {:get_block, block_hash})
  end

  @doc """
  Get a block directly from a specific partition (when you know the partition).
  """
  @spec get_block_from_partition(binary(), String.t()) :: {:ok, Block.t()} | {:error, :not_found}
  def get_block_from_partition(block_hash, partition) do
    GenServer.call(__MODULE__, {:get_block_from_partition, block_hash, partition})
  end

  @doc """
  Check if a block exists in any partition.
  """
  @spec has_block?(binary()) :: boolean()
  def has_block?(block_hash) do
    case get_block(block_hash) do
      {:ok, _} -> true
      {:error, :not_found} -> false
    end
  end

  @doc """
  Get storage statistics across all partitions.
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  List all available partitions.
  """
  @spec list_partitions() :: [String.t()]
  def list_partitions do
    GenServer.call(__MODULE__, :list_partitions)
  end

  # GenServer Callbacks

  @impl true
  def init(opts) do
    # Use configurable base path with node prefix support
    db_path = Keyword.get(opts, :db_path, Bastille.Infrastructure.Storage.CubDB.Paths.blocks_path())
    File.mkdir_p!(db_path)

    # Initialize block partition management
    current_partition = get_current_partition()
    {:ok, current_blocks_db} = get_or_create_blocks_db(db_path, current_partition)

    # Load existing block databases
    blocks_dbs = load_existing_blocks_dbs(db_path)
    blocks_dbs = Map.put(blocks_dbs, current_partition, current_blocks_db)

    state = %__MODULE__{
      blocks_dbs: blocks_dbs,
      current_blocks_db: current_blocks_db,
      current_partition: current_partition,
      db_path: db_path
    }

    Logger.info("📁 Time-partitioned block storage initialized at #{db_path}")
    Logger.info("   ├── blocks#{current_partition}.cubdb (current blocks)")
    Logger.info("📅 Block partitions loaded: #{map_size(blocks_dbs)} month(s)")

    {:ok, state}
  end

  @impl true
  def handle_call({:store_block, block}, _from, state) do
    # Check if we need to rotate to a new partition
    state = maybe_rotate_partition(state)

    block_hash = block.hash
    block_data = :erlang.term_to_binary(block)

    case CubDB.put(state.current_blocks_db, {:block, block_hash}, block_data) do
      :ok ->
        Logger.debug("📦 Block stored: #{Base.encode16(block_hash, case: :lower) |> String.slice(0, 16)}... in partition #{state.current_partition}")
        {:reply, :ok, state}
      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:get_block, block_hash}, _from, state) do
    # FAST: Use index to find the exact partition first
    case Index.find_block_partition(block_hash) do
      {:ok, partition} ->
        # Direct partition access - MUCH faster!
        case Map.get(state.blocks_dbs, partition) do
          nil -> {:reply, {:error, :not_found}, state}
          db ->
            case CubDB.get(db, {:block, block_hash}) do
              nil -> {:reply, {:error, :not_found}, state}
              block_data ->
                block = :erlang.binary_to_term(block_data)
                Logger.debug("📦 Block found via index: partition #{partition}")
                {:reply, {:ok, block}, state}
            end
        end

      {:error, :not_found} ->
        # Fallback: Search all partitions (for blocks indexed before this optimization)
        Logger.debug("📦 Block not in index, falling back to full search")
        partitions = state.blocks_dbs |> Map.keys() |> Enum.sort(:desc)
        result = find_block_in_partitions(partitions, state.blocks_dbs, block_hash)

        # If found via fallback, add to index for future fast lookups
        case result do
          {:ok, block} ->
            correct_partition = get_partition_from_timestamp(block.header.timestamp)
            Index.index_block(block_hash, correct_partition, block.header.timestamp)
            Logger.debug("📦 Block indexed for future fast lookup in partition #{correct_partition}")
          _ -> :ok
        end

        {:reply, result, state}
    end
  end

  @impl true
  def handle_call({:get_block_from_partition, block_hash, partition}, _from, state) do
    case Map.get(state.blocks_dbs, partition) do
      nil -> {:reply, {:error, :not_found}, state}
      db ->
        case CubDB.get(db, {:block, block_hash}) do
          nil -> {:reply, {:error, :not_found}, state}
          block_data ->
            block = :erlang.binary_to_term(block_data)
            {:reply, {:ok, block}, state}
        end
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    partition_stats = Enum.map(state.blocks_dbs, fn {partition, db} ->
      block_count = count_blocks_in_partition(db)
      {partition, block_count}
    end) |> Enum.into(%{})

    total_blocks = partition_stats |> Map.values() |> Enum.sum()

    stats = %{
      total_blocks: total_blocks,
      total_partitions: map_size(state.blocks_dbs),
      partition_stats: partition_stats,
      storage_type: "time_partitioned_monthly",
      current_partition: state.current_partition,
      db_path: state.db_path
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call(:list_partitions, _from, state) do
    partitions = state.blocks_dbs |> Map.keys() |> Enum.sort()
    {:reply, partitions, state}
  end

  # Private functions

  defp get_current_partition do
    {{year, month, _day}, _time} = :calendar.universal_time()
    "#{year}#{String.pad_leading("#{month}", 2, "0")}"
  end

  defp get_partition_from_timestamp(timestamp) do
    # Convert Unix timestamp to date tuple
    datetime = DateTime.from_unix!(timestamp)
    year = datetime.year
    month = datetime.month
    "#{year}#{String.pad_leading("#{month}", 2, "0")}"
  end

  defp get_or_create_blocks_db(db_path, partition) do
    db_file = "blocks#{partition}.cubdb"
    db_dir = Path.join(db_path, db_file)

    # Process-level coordination to prevent simultaneous access
    case CubDB.start_link(data_dir: db_dir, name: :"blocks_#{partition}") do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  defp load_existing_blocks_dbs(db_path) do
    db_path
    |> File.ls!()
    |> Stream.filter(&blocks_db_file?/1)
    |> Stream.map(&extract_partition/1)
    |> Stream.filter(&valid_partition?/1)
    |> Enum.reduce(%{}, &load_partition_db(&1, &2, db_path))
  end

  # Pipeline helpers with pattern matching
  defp blocks_db_file?(filename) do
    String.starts_with?(filename, "blocks") and String.ends_with?(filename, ".cubdb")
  end

  defp valid_partition?(partition), do: partition != nil

  defp load_partition_db(partition, acc, db_path) do
    case get_or_create_blocks_db(db_path, partition) do
      {:ok, db} -> Map.put(acc, partition, db)
      _error -> acc
    end
  end

  defp extract_partition("blocks" <> rest) do
    case String.replace_suffix(rest, ".cubdb", "") do
      <<year::binary-size(4), month::binary-size(2)>> -> year <> month
      _ -> nil
    end
  end

  defp maybe_rotate_partition(state) do
    current_partition = get_current_partition()

    case current_partition != state.current_partition do
      true ->
        Logger.info("📅 Rotating to new block partition: #{current_partition}")
        {:ok, new_blocks_db} = get_or_create_blocks_db(state.db_path, current_partition)
        new_blocks_dbs = Map.put(state.blocks_dbs, current_partition, new_blocks_db)
        %{state |
          blocks_dbs: new_blocks_dbs,
          current_blocks_db: new_blocks_db,
          current_partition: current_partition
        }
      false -> state
    end
  end

  defp find_block_in_partitions([], _blocks_dbs, _block_hash), do: {:error, :not_found}

  defp find_block_in_partitions([partition | rest], blocks_dbs, block_hash) do
    case Map.get(blocks_dbs, partition) do
      nil -> find_block_in_partitions(rest, blocks_dbs, block_hash)
      db ->
        case CubDB.get(db, {:block, block_hash}) do
          nil -> find_block_in_partitions(rest, blocks_dbs, block_hash)
          block_data ->
            block = :erlang.binary_to_term(block_data)
            {:ok, block}
        end
    end
  end

  defp count_blocks_in_partition(db) do
    CubDB.select(db, min_key: {:block, <<>>}, max_key: {:block, <<255>>})
    |> Enum.count()
  rescue
    _ -> 0
  end
end
