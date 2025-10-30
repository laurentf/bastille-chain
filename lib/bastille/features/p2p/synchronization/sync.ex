defmodule Bastille.Features.P2P.Synchronization.Sync do
  @moduledoc """
  Blockchain synchronization protocol for P2P network.

  Handles:
  - Initial blockchain download (IBD)
  - Header-first synchronization
  - Block validation during sync
  - Public key/address state sync
  - Recovery from sync failures
  """

  use GenServer
  require Logger
  # Bitwise is no longer used here

  alias Bastille.Features.Block.Block
  # alias Bastille.Features.P2P.PeerManagement.Peer
  alias Bastille.Features.P2P.Messaging.Messages
  alias Bastille.Features.P2P.PeerManagement.Node

  # Sync configuration constants (will be used in headers-first implementation)
  # @sync_batch_size 500      # Blocks to request at once
  # @sync_timeout 30_000      # 30 seconds timeout per batch
  # @max_sync_peers 3         # Max peers to sync from simultaneously

  defstruct [
    :local_height,           # Current local blockchain height
    :target_height,          # Target height from peers
    :sync_state,             # :idle, :syncing, :catching_up
    :sync_peers,             # Map of peer_id => peer_info
    :pending_blocks,         # Map of height => block_hash
    :downloading_ranges,     # Currently downloading block ranges
    :last_sync_time,         # Timestamp of last successful sync
    :sync_stats,             # Statistics for monitoring
    requested_blocks: MapSet.new() # Track requested block hashes
  ]

  @type t :: %__MODULE__{
    local_height: integer(),
    target_height: integer(),
    sync_state: :idle | :syncing | :catching_up,
    sync_peers: map(),
    pending_blocks: map(),
    downloading_ranges: list(),
    last_sync_time: integer(),
    sync_stats: map()
  }

  # Client API

  @doc """
  Start the synchronization manager.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Trigger blockchain synchronization.
  """
  @spec start_sync() :: :ok
  def start_sync do
    GenServer.cast(__MODULE__, :start_sync)
  end

  @doc """
  Get synchronization status.
  """
  @spec get_sync_status() :: map()
  def get_sync_status do
    GenServer.call(__MODULE__, :get_sync_status)
  end

  @doc """
  Handle incoming block during sync.
  """
  @spec handle_sync_block(Block.t(), String.t()) :: :ok
  def handle_sync_block(%Bastille.Features.Block.Block{} = block, from_peer) do
    GenServer.cast(__MODULE__, {:sync_block_received, block, from_peer})
  end

  @doc """
  Handle peer height discovery - trigger sync if peer is ahead.
  """
  @spec peer_height_discovered(non_neg_integer(), String.t()) :: :ok
  def peer_height_discovered(peer_height, peer_id) do
    GenServer.cast(__MODULE__, {:peer_height_discovered, peer_height, peer_id})
  end

  @doc """
  Build headers to reply to a getheaders request starting from a given height.
  """
  @spec handle_getheaders_request(non_neg_integer()) :: [map()]
  def handle_getheaders_request(start_height) when is_integer(start_height) and start_height >= 0 do
    local_height = safe_get_height()
    end_height = min(local_height, start_height + 200)
    build_headers_range(start_height + 1, end_height)
  end

  @doc """
  Process incoming headers from a peer and request corresponding blocks.
  """
  @spec process_headers_from(String.t(), list()) :: :ok
  def process_headers_from(peer_id, raw_headers) when is_list(raw_headers) do
    Enum.each(raw_headers, fn header_term ->
      case safe_decode_header(header_term) do
        {:ok, header_map} ->
          index = Map.get(header_map, :index) || Map.get(header_map, "index")
          hash = Map.get(header_map, :hash) || Map.get(header_map, "hash")
          req_hash =
            cond do
              is_binary(hash) -> hash
              is_integer(index) ->
                case Bastille.Features.Chain.Chain.get_block_hash_at_height(index) do
                  {:ok, h} -> h
                  _ -> nil
                end
              true -> nil
            end

          if is_binary(req_hash) do
            # Avoid re-entrancy: use cast to Node via its message loop
            GenServer.cast(Bastille.Features.P2P.PeerManagement.Node, {:send_to_peer_async, peer_id, :getdata, Messages.getdata_message([{:block, req_hash}])[:getdata]})
            GenServer.cast(__MODULE__, {:track_requested_block, req_hash})
          end
        _ -> :ok
      end
    end)
    :ok
  end

  @doc """
  Request a missing parent block if not already requested.
  """
  @spec request_parent_if_needed(String.t(), binary()) :: :ok
  def request_parent_if_needed(peer_id, parent_hash) when is_binary(parent_hash) do
    GenServer.cast(__MODULE__, {:request_parent_if_needed, peer_id, parent_hash})
  end

  # GenServer Callbacks

  @impl true
  def init(_opts) do
    # Get current blockchain height
    local_height = safe_get_height()

    state = %__MODULE__{
      local_height: local_height,
      target_height: local_height,
      sync_state: :idle,
      sync_peers: %{},
      pending_blocks: %{},
      downloading_ranges: [],
      last_sync_time: System.system_time(:second),
      sync_stats: %{
        blocks_downloaded: 0,
        bytes_downloaded: 0,
        sync_speed: 0,
        sync_start_time: nil,
        estimated_completion: nil
      }
    }

    Logger.info("🔄 Blockchain sync manager started (local height: #{local_height})")

    # Start sync check timer
    Process.send_after(self(), :check_sync_needed, 5_000)

    {:ok, state}
  end

  @impl true
  def handle_cast(:start_sync, state) do
    Logger.info("🚀 Starting blockchain synchronization...")
    new_state = start_initial_sync(state)
    {:noreply, new_state}
  end

  def handle_cast({:sync_block_received, block, from_peer}, state) do
    new_state = process_sync_block(block, from_peer, state)
    {:noreply, new_state}
  end

  def handle_cast({:peer_height_discovered, peer_height, peer_id}, state) do
    new_state = handle_peer_height(peer_height, peer_id, state)
    {:noreply, new_state}
  end

  def handle_cast({:track_requested_block, req_hash}, state) do
    {:noreply, %{state | requested_blocks: MapSet.put(state.requested_blocks, req_hash)}}
  end

  def handle_cast({:request_parent_if_needed, peer_id, parent_hash}, state) do
    cond do
      not is_binary(parent_hash) -> {:noreply, state}
      MapSet.member?(state.requested_blocks, parent_hash) -> {:noreply, state}
      true ->
        Logger.info("🧩 Requesting parent block #{Base.encode16(parent_hash, case: :lower) |> String.slice(0, 12)}")
        getdata_msg = Messages.getdata_message([{:block, parent_hash}])
        _ = Node.send_to_peer(peer_id, :getdata, getdata_msg[:getdata])
        {:noreply, %{state | requested_blocks: MapSet.put(state.requested_blocks, parent_hash)}}
    end
  end

  @impl true
  def handle_call(:get_sync_status, _from, state) do
    status = %{
      local_height: state.local_height,
      target_height: state.target_height,
      sync_state: state.sync_state,
      sync_progress: calculate_sync_progress(state),
      active_peers: map_size(state.sync_peers),
      pending_blocks: map_size(state.pending_blocks),
      stats: state.sync_stats
    }
    {:reply, status, state}
  end

  @impl true
  def handle_info(:check_sync_needed, state) do
    new_state = check_and_start_sync_if_needed(state)

    # Schedule next check
    Process.send_after(self(), :check_sync_needed, 30_000)

    {:noreply, new_state}
  end

  def handle_info({:sync_timeout, range}, state) do
    Logger.warning("⏰ Sync timeout for range #{inspect(range)}")
    new_state = handle_sync_timeout(range, state)
    {:noreply, new_state}
  end

  def handle_info(msg, state) do
    Logger.debug("🤷 Unknown sync message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private functions

  defp handle_peer_height(peer_height, peer_id, state) do
    Logger.debug("📏 Peer #{peer_id} height: #{peer_height}, local: #{state.local_height}")

    # Update peer info
    updated_peers = Map.put(state.sync_peers, peer_id, %{
      peer_id: peer_id,
      height: peer_height,
      last_seen: System.system_time(:second)
    })

    # Check if we need to sync
    if peer_height > state.local_height + 1 do
      Logger.info("🔄 Peer #{peer_id} is ahead (#{peer_height} vs #{state.local_height}), starting sync...")

      new_state = %{state |
        sync_peers: updated_peers,
        target_height: max(state.target_height, peer_height)
      }

      # Start sync if not already syncing
      if state.sync_state == :idle do
        start_initial_sync(new_state)
      else
        new_state
      end
    else
      # Peer is not ahead, just update peer info
      %{state | sync_peers: updated_peers}
    end
  end

  defp start_initial_sync(state) do
    # Get available peers
    peers = Node.get_peers()
    sync_peers = filter_sync_capable_peers(peers)

    case Enum.empty?(sync_peers) do
      true ->
        Logger.warning("⚠️ No sync-capable peers available")
        %{state | sync_state: :idle}
      false ->
        Logger.info("🔗 Found #{length(sync_peers)} sync-capable peers")
        request_headers_from_peers(sync_peers)
        %{state |
          sync_state: :syncing,
          sync_peers: Enum.into(sync_peers, %{}, fn peer -> {peer.peer_id, peer} end)
        }
    end
  end

  defp check_and_start_sync_if_needed(state) do
    peers = Node.get_peers()

    # Refresh local height from chain to track progress
    local_height = safe_get_height()

    # Check if any peer has higher height
    max_peer_height = peers
    |> Enum.map(fn peer -> get_peer_height(peer) end)
    |> Enum.max(fn -> local_height end)

    case {max_peer_height > local_height and state.sync_state == :idle,
          state.sync_state != :idle and local_height >= state.target_height} do
      {true, _} ->
        Logger.info("📈 Peer has higher height (#{max_peer_height} vs #{local_height}), starting sync...")
        start_initial_sync(%{state | target_height: max_peer_height, local_height: local_height})
      {_, true} ->
        Logger.info("✅ Synced; now processing normally incoming blocks")
        %{state | sync_state: :idle, local_height: local_height, target_height: local_height}
      _ ->
        %{state | local_height: local_height, target_height: max(state.target_height, max_peer_height)}
    end
  end

  defp filter_sync_capable_peers(peers) do
    # Filter peers that are connected and capable of sync
    Enum.filter(peers, fn peer ->
      peer.state == :connected and
      peer.peer_id != nil and
      get_peer_height(peer) > 0
    end)
  end

  defp request_headers_from_peers(peers) do
    # Request headers starting from our current height
    local_height = safe_get_height()

    Enum.each(peers, fn peer ->
      getheaders_msg = Messages.getheaders_message(local_height, 0)
      case Node.send_to_peer(peer.peer_id, :getheaders, getheaders_msg[:getheaders]) do
        :ok -> Logger.debug("📤 Requested headers from #{peer.peer_id} starting at height #{local_height}")
        {:error, reason} -> Logger.warning("⚠️ Failed to request headers from #{peer.peer_id}: #{inspect(reason)}")
      end
    end)
  end

  defp process_sync_block(block, from_peer, state) do
    # Validate and add block during sync
    case validate_sync_block(block, state) do
      :ok ->
        case add_block_to_chain(block) do
          {:ok, _} ->
            Logger.info("✅ Sync block #{block.header.index} added from #{from_peer}")

            new_local_height = state.local_height + 1
            new_stats = update_sync_stats(state.sync_stats, block)

            # Check if sync is complete
    case new_local_height >= state.target_height do
      true ->
        Logger.info("🎉 Blockchain sync completed! Height: #{new_local_height}")
        %{state |
          local_height: new_local_height,
          sync_state: :idle,
          sync_stats: new_stats
        }
      false ->
        %{state |
          local_height: new_local_height,
          sync_stats: new_stats
        }
    end

          {:error, reason} ->
            Logger.error("❌ Failed to add sync block #{block.header.index}: #{inspect(reason)}")
            state
        end

      {:error, reason} ->
        Logger.warning("⚠️ Invalid sync block #{block.header.index} from #{from_peer}: #{inspect(reason)}")
        state
    end
  end

  defp validate_sync_block(block, _state) do
    # Enhanced validation for sync blocks
    with :ok <- validate_block_structure(block),
         :ok <- validate_block_hash(block),
         :ok <- validate_block_transactions(block),
         :ok <- validate_block_chain_continuity(block) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_block_structure(%Bastille.Features.Block.Block{header: header, transactions: txs}) do
    cond do
      not is_map(header) -> {:error, :invalid_header}
      not is_list(txs) -> {:error, :invalid_transactions}
      not is_integer(header.index) -> {:error, :invalid_index}
      not is_binary(header.previous_hash) -> {:error, :invalid_previous_hash}
      true -> :ok
    end
  end

  defp validate_block_hash(%Bastille.Features.Block.Block{hash: hash, header: header, transactions: txs}) do
    # Verify block hash matches content
    calculated_hash = calculate_block_hash(header, txs)

    # Constant-time comparison to avoid timing leaks
    case Bastille.Features.P2P.Messaging.Validation.secure_equal(hash, calculated_hash) do
      true -> :ok
      _ -> {:error, :hash_mismatch}
    end
  end

  defp validate_block_transactions(%Bastille.Features.Block.Block{transactions: transactions}) do
    # Validate each transaction in the block
    Enum.reduce_while(transactions, :ok, fn tx, _acc ->
      case validate_transaction_in_sync(tx) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:invalid_transaction, reason}}}
      end
    end)
  end

  defp validate_block_chain_continuity(%Bastille.Features.Block.Block{header: %{index: index, previous_hash: prev_hash}}) do
    # Verify block connects to existing chain
    current_height = safe_get_height()

    cond do
      index == current_height + 1 ->
        # Next expected block
        case get_current_head_hash() do
          ^prev_hash -> :ok
          _ -> {:error, :chain_break}
        end
      index <= current_height ->
        # Old block (might be reorganization)
        {:error, :old_block}
      index > current_height + 1 ->
        # Future block (missing intermediate blocks)
        {:error, :future_block}
    end
  end

  defp validate_transaction_in_sync(tx) do
    # Basic transaction validation during sync
    # More permissive than real-time validation
    case Bastille.Features.Mining.MiningCoordinator.validate_transaction(tx) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp add_block_to_chain(block) do
    # Add block using existing blockchain logic
    Bastille.Features.Chain.Chain.add_block(block)
  end

  defp calculate_block_hash(header, transactions) do
    # Use existing block hash calculation
    Bastille.Features.Block.Block.calculate_hash(%Bastille.Features.Block.Block{header: header, transactions: transactions})
  end

  defp get_current_head_hash do
    case Bastille.Features.Chain.Chain.get_head_block() do
      {:ok, {_height, hash}} -> hash
      _ -> String.duplicate("0", 64)  # Genesis case
    end
  end

  # secure compare moved to Bastille.Features.P2P.Messaging.Validation

  defp safe_get_height do
    try do
      Bastille.Features.Chain.Chain.get_height()
    catch
      :exit, _ -> 0
    end
  end

  defp get_peer_height(peer) do
    # Extract height from peer info (from version message)
    case Map.get(peer, :peer_info) do
      %{"start_height" => height} when is_integer(height) -> height
      _ -> 0
    end
  end

  defp calculate_sync_progress(%{local_height: local, target_height: target}) do
    case target > 0 do
      true -> min(100.0, (local / target) * 100.0)
      false -> 100.0
    end
  end

  defp update_sync_stats(stats, block) do
    block_size = byte_size(:erlang.term_to_binary(block))
    new_blocks_downloaded = stats.blocks_downloaded + 1
    sync_start_time = stats.sync_start_time || System.system_time(:second)

    base_stats = %{
      stats |
      blocks_downloaded: new_blocks_downloaded,
      bytes_downloaded: stats.bytes_downloaded + block_size,
      sync_start_time: sync_start_time
    }

    %{base_stats | sync_speed: calculate_sync_speed(base_stats)}
  end

  # Helpers for headers flow
  defp build_headers_range(start_h, end_h) when end_h >= start_h do
    Enum.reduce(start_h..end_h, [], fn h, acc ->
      case Bastille.Features.Chain.Chain.get_block_hash_at_height(h) do
        {:ok, block_hash} ->
          case Bastille.Features.Chain.Chain.get_block(block_hash) do
            %Bastille.Features.Block.Block{header: header, hash: hash} ->
              header_with_hash = %{
                index: header.index,
                previous_hash: header.previous_hash,
                timestamp: header.timestamp,
                merkle_root: header.merkle_root,
                nonce: header.nonce,
                difficulty: header.difficulty,
                hash: hash
              }
              [header_with_hash | acc]
            _ -> acc
          end
        _ -> acc
      end
    end) |> Enum.reverse()
  end

  defp build_headers_range(_start_h, _end_h), do: []

  defp safe_decode_header(%{} = map), do: {:ok, map}
  defp safe_decode_header(bin) when is_binary(bin) do
    try do
      {:ok, :erlang.binary_to_term(bin)}
    rescue
      _ -> {:error, :invalid_header}
    end
  end

  defp calculate_sync_speed(stats) do
    # Calculate blocks per second since sync started
    start_time = stats.sync_start_time || System.system_time(:second)
    elapsed = System.system_time(:second) - start_time
    case elapsed > 0 do
      true -> stats.blocks_downloaded / elapsed
      false -> 0.0
    end
  end

  defp handle_sync_timeout(_range, state) do
    # TODO: Implement timeout handling for headers-first sync
    # This will be expanded when implementing parallel block download
    Logger.warning("⚠️ Sync timeout handling not yet implemented")
    state
  end
end
