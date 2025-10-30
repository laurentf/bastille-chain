defmodule Bastille.Features.Chain.OrphanManager do
  @moduledoc """
  Manages orphan blocks (received before their parent) in-memory.

  Scope: Chain management concern (chain continuity), not transaction mempool.
  Data is transient (RAM only), like Bitcoin behavior.
  """

  use GenServer
  require Logger

  alias Bastille.Features.Block.Block

  @default_max_orphans 500
  @default_max_orphan_age_ms 600_000 # 10 minutes
  @cleanup_interval_ms 60_000        # every minute

  defstruct orphan_blocks: %{},          # %{block_hash => %{block: Block.t(), received_at: ms}}
            blocks_by_parent: %{},       # %{parent_hash => [block_hash, ...]}
            max_orphans: @default_max_orphans,
            max_orphan_age_ms: @default_max_orphan_age_ms

  @type t :: %__MODULE__{
          orphan_blocks: %{binary() => %{block: Block.t(), received_at: integer()}},
          blocks_by_parent: %{binary() => [binary()]},
          max_orphans: pos_integer(),
          max_orphan_age_ms: pos_integer()
        }

  # Client API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @spec add_orphan_block(Block.t()) :: :ok | {:error, term()}
  def add_orphan_block(%Block{} = block), do: GenServer.call(__MODULE__, {:add_orphan, block})

  @spec get_orphan_blocks_by_parent(binary()) :: [Block.t()]
  def get_orphan_blocks_by_parent(parent_hash),
    do: GenServer.call(__MODULE__, {:get_by_parent, parent_hash})

  @spec process_orphans_for_parent(binary()) :: [Block.t()]
  def process_orphans_for_parent(parent_hash),
    do: GenServer.call(__MODULE__, {:process_for_parent, parent_hash})

  @spec get_stats() :: %{count: non_neg_integer(), oldest_age_ms: non_neg_integer()}
  def get_stats, do: GenServer.call(__MODULE__, :stats)

  @spec clear() :: :ok
  def clear, do: GenServer.call(__MODULE__, :clear)

  # GenServer callbacks

  @impl true
  def init(opts) do
    state = %__MODULE__{
      max_orphans: Keyword.get(opts, :max_orphans, @default_max_orphans),
      max_orphan_age_ms: Keyword.get(opts, :max_orphan_age_ms, @default_max_orphan_age_ms)
    }

    Process.send_after(self(), :cleanup_expired, @cleanup_interval_ms)
    Logger.info("🔄 OrphanManager started (max=#{state.max_orphans}, max_age=#{div(state.max_orphan_age_ms, 60_000)}min)")
    {:ok, state}
  end

  @impl true
  def handle_call({:add_orphan, %Block{} = block}, _from, %__MODULE__{} = state) do
    case validate_and_add(block, state) do
      {:ok, new_state} ->
        Logger.info("🔄 Orphan block #{block.header.index} queued (parent #{short(block.header.previous_hash)})")
        {:reply, :ok, new_state}
      {:error, reason} = err ->
        Logger.warning("⚠️ Orphan rejected: #{inspect(reason)}")
        {:reply, err, state}
    end
  end

  @impl true
  def handle_call({:get_by_parent, parent_hash}, _from, %__MODULE__{} = state) do
    blocks = parent_hash |> Map.get(state.blocks_by_parent, []) |> Enum.map(&state.orphan_blocks[&1].block)
    {:reply, blocks, state}
  end

  @impl true
  def handle_call({:process_for_parent, parent_hash}, _from, %__MODULE__{} = state) do
    block_hashes = Map.get(state.blocks_by_parent, parent_hash, [])
    blocks = Enum.map(block_hashes, &state.orphan_blocks[&1].block)
    new_state = remove_orphans(block_hashes, state)
    Logger.info("🔄 Processing #{length(blocks)} orphan(s) for parent #{short(parent_hash)}")
    {:reply, blocks, new_state}
  end

  @impl true
  def handle_call(:stats, _from, %__MODULE__{} = state) do
    count = map_size(state.orphan_blocks)
    oldest =
      if count == 0 do
        0
      else
        now = System.system_time(:millisecond)
        state.orphan_blocks |> Map.values() |> Enum.map(&(now - &1.received_at)) |> Enum.max()
      end
    {:reply, %{count: count, oldest_age_ms: oldest}, state}
  end

  @impl true
  def handle_call(:clear, _from, %__MODULE__{} = state) do
    {:reply, :ok, %{state | orphan_blocks: %{}, blocks_by_parent: %{}}}
  end

  @impl true
  def handle_info(:cleanup_expired, %__MODULE__{} = state) do
    new_state = cleanup_expired(state)
    Process.send_after(self(), :cleanup_expired, @cleanup_interval_ms)
    {:noreply, new_state}
  end

  # Internal

  defp validate_and_add(%Block{} = block, %__MODULE__{} = state) do
    with :ok <- valid_block_shape(block),
         :ok <- check_capacity(state),
         false <- exists?(block.hash, state) do
      {:ok, put_orphan(block, state)}
    else
      true -> {:error, :already_exists}
      error -> error
    end
  end

  defp valid_block_shape(%Block{} = block) do
    if is_binary(block.hash) and is_binary(block.header.previous_hash), do: :ok, else: {:error, :invalid_structure}
  end

  defp check_capacity(%__MODULE__{orphan_blocks: orphans, max_orphans: max}) do
    if map_size(orphans) < max, do: :ok, else: {:error, :pool_full}
  end

  defp exists?(hash, %__MODULE__{orphan_blocks: orphans}), do: Map.has_key?(orphans, hash)

  defp put_orphan(%Block{} = block, %__MODULE__{} = state) do
    now = System.system_time(:millisecond)
    orphan_blocks = Map.put(state.orphan_blocks, block.hash, %{block: block, received_at: now})
    parent = block.header.previous_hash
    blocks_by_parent = Map.update(state.blocks_by_parent, parent, [block.hash], &[block.hash | &1])
    %{state | orphan_blocks: orphan_blocks, blocks_by_parent: blocks_by_parent}
  end

  defp remove_orphans(block_hashes, %__MODULE__{} = state) do
    orphan_blocks = Map.drop(state.orphan_blocks, block_hashes)
    blocks_by_parent =
      state.blocks_by_parent
      |> Enum.map(fn {parent, children} -> {parent, children -- block_hashes} end)
      |> Enum.reject(fn {_p, children} -> children == [] end)
      |> Map.new()
    %{state | orphan_blocks: orphan_blocks, blocks_by_parent: blocks_by_parent}
  end

  defp cleanup_expired(%__MODULE__{} = state) do
    now = System.system_time(:millisecond)
    cutoff = now - state.max_orphan_age_ms
    expired =
      state.orphan_blocks
      |> Enum.filter(fn {_h, %{received_at: t}} -> t < cutoff end)
      |> Enum.map(fn {h, _} -> h end)
    if expired == [] do
      state
    else
      Logger.info("🧹 Cleaning #{length(expired)} expired orphan blocks")
      remove_orphans(expired, state)
    end
  end

  defp short(hash) when is_binary(hash), do: hash |> Base.encode16() |> String.slice(0, 8)
end
