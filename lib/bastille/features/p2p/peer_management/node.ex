defmodule Bastille.Features.P2P.PeerManagement.Node do
  @moduledoc """
  Node coordinator for managing multiple P2P peer connections.

  Handles:
  - Multiple peer connections
  - Block/transaction broadcasting
  - Peer discovery and management
  - Integration with blockchain events
  """

  use GenServer
  require Logger

  alias Bastille.Features.P2P.PeerManagement.Peer
  alias Bastille.Features.P2P.Messaging.Messages
  alias Bastille.Features.P2P.Synchronization.Sync
  alias Bastille.Features.Block.Block
  alias Bastille.Features.Transaction.Transaction

  @max_peers 8
  @retry_interval 30_000  # 30 seconds
  @ping_interval 30_000
  @pong_timeout 60_000

  defstruct [
    :listen_socket,
    :port,
    :node_id,
    last_known_height: 0,
    peers: %{},              # %{peer_id => peer_pid}
    peer_addresses: %{},     # %{peer_id => {address, port}}
    bootstrap_peers: [],     # [{address, port}]
    blocks_seen: MapSet.new(),
    transactions_seen: MapSet.new(),
    last_pong: %{}, # %{peer_id => timestamp}
    requested_blocks: MapSet.new() # track requested block hashes to avoid duplicates
  ]

  @type t :: %__MODULE__{
    listen_socket: :gen_tcp.socket() | nil,
    port: integer(),
    node_id: String.t(),
    peers: map(),
    peer_addresses: map(),
    bootstrap_peers: list(),
    blocks_seen: MapSet.t(),
    transactions_seen: MapSet.t()
  }

  # Client API

  @doc """
  Start the P2P node.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Connect to a new peer.
  """
  @spec connect_peer(String.t(), integer()) :: :ok | {:error, term()}
  def connect_peer(address, port) do
    GenServer.call(__MODULE__, {:connect_peer, address, port})
  end

  @doc """
  Broadcast a block to all connected peers.
  """
  @spec broadcast_block(Block.t()) :: :ok
  def broadcast_block(%Bastille.Features.Block.Block{} = block) do
    GenServer.cast(__MODULE__, {:broadcast_block, block})
  end

  @doc """
  Broadcast a transaction to all connected peers.
  """
  @spec broadcast_transaction(Transaction.t()) :: :ok
  def broadcast_transaction(%Bastille.Features.Transaction.Transaction{} = transaction) do
    GenServer.cast(__MODULE__, {:broadcast_transaction, transaction})
  end

  @doc """
  Get list of connected peers.
  """
  @spec get_peers() :: [map()]
  def get_peers do
    GenServer.call(__MODULE__, :get_peers)
  end

  @doc """
  Send a message to a specific peer by `peer_id` ("ip:port").
  """
  @spec send_to_peer(String.t(), atom(), any()) :: :ok | {:error, term()}
  def send_to_peer(peer_id, command, payload) do
    GenServer.call(__MODULE__, {:send_to_peer, peer_id, command, payload})
  end

  @doc """
  Get node status.
  """
  @spec get_status() :: map()
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  # GenServer Callbacks

  @impl true
  def init(opts) do
    port = Keyword.get(opts, :port, 8333)
    bootstrap_peers = Keyword.get(opts, :bootstrap_peers, [])

    # Generate unique node ID
    node_id = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)

    Logger.info("🌐 Starting P2P Node on port #{port}")
    Logger.info("   └─ Node ID: #{String.slice(node_id, 0, 16)}...")

    state = %__MODULE__{
      port: port,
      node_id: node_id,
      bootstrap_peers: bootstrap_peers
    }

    # Start listening for incoming connections
    send(self(), :start_listening)

    # Connect to bootstrap peers
    send(self(), :connect_bootstrap_peers)

    # Start peer maintenance timer
    Process.send_after(self(), :maintain_peers, @retry_interval)
    # Start liveness checks
    Process.send_after(self(), :ping_peers, @ping_interval)

    {:ok, state}
  end

  @impl true
  def handle_call({:connect_peer, address, port}, _from, state) do
    case start_outbound_peer(address, port, state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:get_peers, _from, state) do
    peer_list = state.peers
    |> Enum.filter(fn {_peer_id, peer_pid} -> Process.alive?(peer_pid) end)
    |> Enum.map(fn {peer_id, peer_pid} ->
      case Peer.get_status(peer_pid) do
        {:error, _} -> nil
        status when is_map(status) ->
          %{
            peer_id: peer_id,
            address: status.address,
            port: status.port,
            state: status.state,
            direction: status.direction,
            peer_info: status.peer_info
          }
      end
    end)
    |> Enum.reject(&is_nil/1)
    {:reply, peer_list, state}
  end

  def handle_call({:send_to_peer, peer_id, command, payload}, _from, state) do
    case Map.get(state.peers, peer_id) do
      nil -> {:reply, {:error, :peer_not_found}, state}
      peer_pid when is_pid(peer_pid) ->
        result = Peer.send_message(peer_pid, command, payload)
        {:reply, result, state}
    end
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      node_id: state.node_id,
      port: state.port,
      connected_peers: map_size(state.peers),
      blocks_seen: MapSet.size(state.blocks_seen),
      transactions_seen: MapSet.size(state.transactions_seen),
      listening: state.listen_socket != nil
    }
    {:reply, status, state}
  end

  @impl true
  def handle_cast({:broadcast_block, %Block{} = block}, %__MODULE__{} = state) do
    seen? = MapSet.member?(state.blocks_seen, block.hash)
    do_broadcast_block(seen?, block, state)
  end

  @impl true
  def handle_cast({:broadcast_transaction, %Transaction{} = transaction}, %__MODULE__{} = state) do
    seen? = MapSet.member?(state.transactions_seen, transaction.hash)
    do_broadcast_transaction(seen?, transaction, state)
  end

  def handle_cast({:send_to_peer_async, peer_id, command, payload}, state) do
    case Map.get(state.peers, peer_id) do
      nil -> :ok
      peer_pid when is_pid(peer_pid) -> _ = Peer.send_message(peer_pid, command, payload)
    end
    {:noreply, state}
  end

  @impl true
  def handle_info(:start_listening, state) do
    case :gen_tcp.listen(state.port, [
      :binary,
      {:active, false},
      {:reuseaddr, true},
      {:packet, :raw}
    ]) do
      {:ok, listen_socket} ->
        Logger.info("👂 P2P Node listening on port #{state.port}")
        spawn_link(fn -> accept_connections(listen_socket, state.port, state.node_id) end)
        {:noreply, %{state | listen_socket: listen_socket}}

      {:error, reason} ->
        Logger.error("❌ Failed to listen on port #{state.port}: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_info(:connect_bootstrap_peers, state) do
    Enum.each(state.bootstrap_peers, fn {address, port} ->
      Logger.info("🔗 Connecting to bootstrap peer #{address}:#{port}")
      start_outbound_peer(address, port, state)
    end)
    {:noreply, state}
  end

  def handle_info(:maintain_peers, state) do
    # Remove disconnected peers
    active_peers = Enum.filter(state.peers, fn {_peer_id, peer_pid} ->
      Process.alive?(peer_pid)
    end) |> Map.new()

    # Try to maintain minimum number of connections
    peer_count = map_size(active_peers)
    if peer_count < @max_peers and not Enum.empty?(state.bootstrap_peers) do
      # Get currently connected addresses to avoid duplicates
      connected_addresses = active_peers
      |> Enum.map(fn {peer_id, _pid} ->
        Map.get(state.peer_addresses, peer_id)
      end)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

      # Find bootstrap peers we're not already connected to
      available_bootstrap = state.bootstrap_peers
      |> Enum.reject(fn {addr, port} ->
        MapSet.member?(connected_addresses, {addr, port})
      end)

      if not Enum.empty?(available_bootstrap) do
        {address, port} = Enum.random(available_bootstrap)
        Logger.info("🔗 Connecting to new bootstrap peer #{address}:#{port} (#{peer_count}/#{@max_peers} connected)")
        start_outbound_peer(address, port, state)
      else
        Logger.debug("📊 All bootstrap peers already connected (#{peer_count}/#{@max_peers})")
      end
    end

    # Schedule next maintenance
    Process.send_after(self(), :maintain_peers, @retry_interval)

    {:noreply, %{state | peers: active_peers}}
  end

  def handle_info(:ping_peers, state) do
    now = System.system_time(:millisecond)
    Enum.each(state.peers, fn {peer_id, peer_pid} ->
      if Process.alive?(peer_pid) do
        nonce = :rand.uniform(0xFFFFFFFF)
        _ = Peer.send_message(peer_pid, :ping, nonce)
      end
      # Evict stale peers with no pong for too long
      last = Map.get(state.last_pong, peer_id, now)
      if now - last > @pong_timeout do
        Logger.warning("⏳ Peer unresponsive (no pong): #{peer_id}")
        if Process.alive?(peer_pid), do: Peer.disconnect(peer_pid)
      end
    end)
    Process.send_after(self(), :ping_peers, @ping_interval)
    {:noreply, state}
  end

  # Remove monitored peers immediately when they die
  def handle_info({:DOWN, _mref, :process, peer_pid, _reason}, state) do
    {peer_id, _} = Enum.find(state.peers, fn {_id, pid} -> pid == peer_pid end) || {nil, nil}
    if peer_id do
      Logger.info("👋 Peer down: #{peer_id}")
      new_peers = Map.delete(state.peers, peer_id)
      new_addresses = Map.delete(state.peer_addresses, peer_id)
      {:noreply, %{state | peers: new_peers, peer_addresses: new_addresses}}
    else
      {:noreply, state}
    end
  end

  def handle_info({:peer_connected, peer_pid, address, port}, state) do
    peer_id = generate_peer_id(address, port)

    Logger.info("✅ Peer connected: #{address}:#{port} (#{peer_id})")

    # Send height message to discover peer's blockchain height
    local_height = try do
          Bastille.Features.Chain.Chain.get_height()
    catch
      :exit, _ -> state.last_known_height
    end

    height_msg = Messages.height_message(local_height)

    # Send height message (peer might disconnect before we send)
    try do
      Peer.send_message(peer_pid, :height, height_msg[:height])
    catch
      :exit, _ ->
        Logger.debug("📏 Peer disconnected before height exchange: #{address}:#{port}")
    end

    # Prevent duplicate connections to the same remote endpoint
    if Map.has_key?(state.peers, peer_id) do
      Logger.debug("🔁 Duplicate connection #{peer_id} detected; keeping existing, dropping new")
      if Process.alive?(peer_pid), do: Peer.disconnect(peer_pid)
      {:noreply, state}
    else
      new_peers = Map.put(state.peers, peer_id, peer_pid)
      new_addresses = Map.put(state.peer_addresses, peer_id, {address, port})
      {:noreply, %{state | peers: new_peers, peer_addresses: new_addresses, last_known_height: max(state.last_known_height, local_height)}}
    end
  end

  def handle_info({:peer_disconnected, peer_pid}, state) do
    # Find and remove the disconnected peer
    {peer_id, _} = Enum.find(state.peers, fn {_id, pid} -> pid == peer_pid end) || {nil, nil}

    if peer_id do
      Logger.info("👋 Peer disconnected: #{peer_id}")
      new_peers = Map.delete(state.peers, peer_id)
      new_addresses = Map.delete(state.peer_addresses, peer_id)
      {:noreply, %{state | peers: new_peers, peer_addresses: new_addresses}}
    else
      {:noreply, state}
    end
  end

  def handle_info({:p2p_message, command, payload, from_address, from_port}, state) do
    # Handle incoming P2P messages
    new_state =
      case command do
        :pong ->
          peer_id = generate_peer_id(from_address, from_port)
          %{state | last_pong: Map.put(state.last_pong, peer_id, System.system_time(:millisecond))}
        _ -> process_p2p_message(command, payload, from_address, from_port, state)
      end
    {:noreply, new_state}
  end

  def handle_info(msg, state) do
    Logger.debug("🤷 Unknown message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private functions

  defp start_outbound_peer(address, port, state) do
    case Peer.start_link_outbound(address, port, local_port: state.port, local_node_id: state.node_id) do
      {:ok, peer_pid} ->
        # Monitor the peer process
        Process.monitor(peer_pid)
        send(self(), {:peer_connected, peer_pid, address, port})
        {:ok, state}

      {:error, reason} ->
        Logger.warning("⚠️ Failed to connect to #{address}:#{port}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp accept_connections(listen_socket, local_port, local_node_id) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, client_socket} ->
        handle_client_socket(client_socket, local_port, local_node_id)
        accept_connections(listen_socket, local_port, local_node_id)
      {:error, reason} ->
        Logger.error("❌ Accept error: #{inspect(reason)}")
        :timer.sleep(1000)
        accept_connections(listen_socket, local_port, local_node_id)
    end
  end

  defp handle_client_socket(client_socket, local_port, local_node_id) do
    {:ok, {address, port}} = :inet.peername(client_socket)
    address_str = :inet.ntoa(address) |> to_string()
    Logger.debug("🔧 Accepted socket from #{address_str}:#{port}, transferring to Peer...")

    case Peer.start_link_inbound(client_socket, address_str, port, local_port: local_port, local_node_id: local_node_id) do
      {:ok, peer_pid} ->
        Logger.debug("✅ Peer process started for #{address_str}:#{port}")
        transfer_socket_control(client_socket, peer_pid, address_str, port)
        Process.monitor(peer_pid)
        send(__MODULE__, {:peer_connected, peer_pid, address_str, port})
      {:error, reason} ->
        Logger.warning("⚠️ Failed to start inbound peer: #{inspect(reason)}")
        :gen_tcp.close(client_socket)
    end
  end

  defp transfer_socket_control(client_socket, peer_pid, address_str, port) do
    case :gen_tcp.controlling_process(client_socket, peer_pid) do
      :ok -> Logger.debug("🔄 Socket control transferred to peer #{address_str}:#{port}")
      {:error, reason} -> Logger.error("❌ Failed to transfer socket control: #{inspect(reason)}")
    end
  end

  defp broadcast_to_peers(command, payload, state) do
    # Filter only alive peers first
    alive_peers = Enum.filter(state.peers, fn {_peer_id, peer_pid} ->
      Process.alive?(peer_pid)
    end)

    Enum.each(alive_peers, fn {peer_id, peer_pid} ->
      try do
        case Peer.send_message(peer_pid, command, payload) do
          :ok ->
            Logger.debug("📤 Sent #{command} to #{peer_id}")
          {:error, reason} ->
            Logger.warning("⚠️ Failed to send #{command} to #{peer_id}: #{inspect(reason)}")
        end
      catch
        :exit, reason ->
          Logger.debug("🔌 Peer #{peer_id} exited during send: #{inspect(reason)}")
      end
    end)
  end

  defp do_broadcast_block(true, %Block{hash: hash}, state) do
    Logger.debug("🔄 Block #{encode_hash(hash)}... already seen, not broadcasting")
    {:noreply, state}
  end
  defp do_broadcast_block(false, %Block{hash: hash}, state) do
    Logger.info("📡 Broadcasting new block #{encode_hash(hash)}... to #{map_size(state.peers)} peers")
    new_state = %{state | blocks_seen: MapSet.put(state.blocks_seen, hash)}
    inv_msg = Messages.inv_message([{:block, hash}])
    broadcast_to_peers(:inv, inv_msg[:inv], new_state)
    {:noreply, new_state}
  end

  defp do_broadcast_transaction(true, %Transaction{hash: hash}, state) do
    Logger.debug("🔄 Transaction #{encode_hash(hash)}... already seen, not broadcasting")
    {:noreply, state}
  end
  defp do_broadcast_transaction(false, %Transaction{hash: hash}, state) do
    Logger.info("📡 Broadcasting new transaction #{encode_hash(hash)}... to #{map_size(state.peers)} peers")
    new_state = %{state | transactions_seen: MapSet.put(state.transactions_seen, hash)}
    inv_msg = Messages.inv_message([{:tx, hash}])
    broadcast_to_peers(:inv, inv_msg[:inv], new_state)
    {:noreply, new_state}
  end

  defp process_p2p_message(:inv, inventory_items, from_address, from_port, state) do
    Logger.info("📦 Received inventory from #{from_address}:#{from_port}: #{length(inventory_items)} items")

    # Process each inventory item
    Enum.each(inventory_items, fn %{"type" => type, "hash" => hash} ->
      handle_inv_item(type, hash, from_address, from_port, state)
    end)

    state
  end



  defp process_p2p_message(:getdata, requested_items, from_address, from_port, state) do
    Logger.info("📨 Received getdata from #{from_address}:#{from_port}: #{length(requested_items)} items")

    case find_peer_by_address(from_address, from_port, state) do
      nil -> state
      peer_pid ->
        Enum.each(requested_items, fn item ->
          process_getdata_item(item, peer_pid, from_address, from_port)
        end)
        state
    end
  end



  defp process_p2p_message(:block, block_data, from_address, from_port, state) do
    Logger.info("📦 Received block from #{from_address}:#{from_port}")

    # Convert and validate P2P block data
    case Bastille.Features.Block.BlockConverter.from_p2p_data(block_data) do
      {:ok, block} ->
        # Try to add block to blockchain
        case Bastille.Features.Chain.Chain.add_block(block) do
          :ok ->
            Logger.info("✅ Block #{block.header.index} (#{encode_hash(block.hash)}) accepted and added to blockchain")
            # Mark as seen and potentially relay to other peers
            new_state = %{state | blocks_seen: MapSet.put(state.blocks_seen, block.hash)}

            # Relay to other peers (except sender)
             sender_peer_id = generate_peer_id(from_address, from_port)
             relay_to_other_peers(:inv, Messages.inv_message([{:block, block.hash}])[:inv], sender_peer_id, new_state)

            new_state

          {:orphan, :added_to_pool} ->
            Logger.info("🔄 Block #{block.header.index} stored as orphan (added to pool, parent unknown)")
            parent_hash = block.header.previous_hash
            new_state = %{state | blocks_seen: MapSet.put(state.blocks_seen, block.hash)}
            request_parent_if_needed(from_address, from_port, parent_hash, new_state)

          {:orphan, parent_hash} when is_binary(parent_hash) ->
            Logger.info("🔄 Block #{block.header.index} stored as orphan (missing parent: #{encode_hash(parent_hash)})")
            new_state = %{state | blocks_seen: MapSet.put(state.blocks_seen, block.hash)}
            request_parent_if_needed(from_address, from_port, parent_hash, new_state)

          {:error, reason} ->
            Logger.warning("❌ Block #{block.header.index} (#{encode_hash(block.hash)}) rejected: #{inspect(reason)}")
            state
        end

      {:error, reason} ->
        Logger.warning("⚠️ Rejected invalid block from #{from_address}:#{from_port}: #{inspect(reason)}")
        state
    end
  end

  # Minimal headers-first sync support
  defp process_p2p_message(:getheaders, %{"block_locator_hashes" => [start_height] = _loc, "hash_stop" => _stop, "version" => _v}, from_address, from_port, state)
       when is_integer(start_height) do
    Logger.info("🧾 getheaders from #{from_address}:#{from_port} starting at height #{start_height}")
    headers = Sync.handle_getheaders_request(start_height)
    case find_peer_by_address(from_address, from_port, state) do
      nil -> :ok
      peer_pid -> _ = Peer.send_message(peer_pid, :headers, Messages.headers_message(headers)[:headers])
    end
    state
  end

  defp process_p2p_message(:headers, %{"count" => count, "headers" => raw_headers}, from_address, from_port, state)
       when is_integer(count) and is_list(raw_headers) do
    Logger.info("🧾 headers (#{count}) from #{from_address}:#{from_port}")
    peer_id = generate_peer_id(from_address, from_port)
    Task.start(fn -> Sync.process_headers_from(peer_id, raw_headers) end)
    state
  end

  defp process_p2p_message(command, payload, from_address, from_port, state) do
    Logger.debug("📨 Unhandled message #{command} from #{from_address}:#{from_port}: #{inspect(payload)}")
    state
  end

  # Helpers extracted from process_p2p_message clauses (kept after all clauses to satisfy grouping)
  defp handle_inv_item("block", hash, from_address, from_port, %__MODULE__{} = state) do
    case MapSet.member?(state.blocks_seen, hash) do
      true -> :ok
      false ->
        Logger.info("🔍 Requesting new block #{encode_hash(hash)}...")
        case find_peer_by_address(from_address, from_port, state) do
          nil -> :ok
          peer_pid ->
            getdata_msg = Messages.getdata_message([{:block, hash}])
            Peer.send_message(peer_pid, :getdata, getdata_msg[:getdata])
        end
    end
  end

  defp handle_inv_item("tx", hash, from_address, from_port, %__MODULE__{} = state) do
    case MapSet.member?(state.transactions_seen, hash) do
      true -> :ok
      false ->
        Logger.info("🔍 Requesting new transaction #{encode_hash(hash)}...")
        case find_peer_by_address(from_address, from_port, state) do
          nil -> :ok
          peer_pid ->
            getdata_msg = Messages.getdata_message([{:tx, hash}])
            Peer.send_message(peer_pid, :getdata, getdata_msg[:getdata])
        end
    end
  end

  defp process_getdata_item(%{"type" => "block", "hash" => hash}, peer_pid, from_address, from_port) do
    case Bastille.Features.Chain.Chain.get_block(hash) do
      %Bastille.Features.Block.Block{} = block ->
        Logger.info("📤 Sending block #{encode_hash(block.hash)} to #{from_address}:#{from_port}")
        block_msg = Messages.block_message(block)
        Peer.send_message(peer_pid, :block, block_msg[:block])
      nil ->
        Logger.warning("⚠️ Block #{encode_hash(hash)}... not found")
    end
  end

  defp process_getdata_item(%{"type" => "tx", "hash" => hash}, _peer_pid, _from_address, _from_port) do
    Logger.info("📨 Transaction #{encode_hash(hash)}... requested (not implemented yet)")
  end

  defp find_peer_by_address(address, port, state) do
    peer_id = generate_peer_id(address, port)
    Map.get(state.peers, peer_id)
  end

  defp relay_to_other_peers(command, payload, exclude_peer_id, state) do
    state.peers
    |> Enum.reject(fn {peer_id, _pid} -> peer_id == exclude_peer_id end)
    |> Enum.filter(fn {_peer_id, peer_pid} -> Process.alive?(peer_pid) end)
    |> Enum.each(fn {peer_id, peer_pid} ->
      case Peer.send_message(peer_pid, command, payload) do
        :ok -> Logger.debug("📤 Relayed #{command} to #{peer_id}")
        {:error, reason} -> Logger.warning("⚠️ Failed to relay #{command} to #{peer_id}: #{inspect(reason)}")
      end
    end)
  end

  defp generate_peer_id(address, port) do
    "#{address}:#{port}"
  end

  defp encode_hash(hash) when is_binary(hash) do
    Base.encode16(hash, case: :lower) |> String.slice(0, 12)
  end



  # moved header helpers into Sync

  defp request_parent_if_needed(from_address, from_port, parent_hash, state) do
    cond do
      not is_binary(parent_hash) -> state
      MapSet.member?(state.blocks_seen, parent_hash) -> state
      MapSet.member?(state.requested_blocks, parent_hash) -> state
      true ->
        case find_peer_by_address(from_address, from_port, state) do
          nil -> :ok
          peer_pid ->
            Logger.info("🧩 Requesting parent block #{encode_hash(parent_hash)}")
            getdata_msg = Messages.getdata_message([{:block, parent_hash}])
            _ = Peer.send_message(peer_pid, :getdata, getdata_msg[:getdata])
        end
        %{state | requested_blocks: MapSet.put(state.requested_blocks, parent_hash)}
    end
  end
end
