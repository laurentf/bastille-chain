defmodule Bastille.Features.P2P.PeerManagement.Peer do
  @moduledoc """
  GenServer representing a single TCP peer connection.

  Uses protobuf wire protocol with length-prefixed framing for type safety and efficiency.
  """

  use GenServer
  require Logger

  alias Bastille.Features.P2P.Messaging.Messages
  alias Bastille.Features.P2P.Messaging.Codec
  alias Bastille.Features.P2P.Messaging.Validation

  @connect_timeout 5_000
  @handshake_timeout 10_000

  defstruct [
    :socket,
    :address,
    :port,
    :state,
    :direction,  # :outbound or :inbound
    :peer_info,
    :node_id,
    :buffer,
    :local_port,
    :local_node_id
  ]

  @type t :: %__MODULE__{
    socket: :gen_tcp.socket() | nil,
    address: String.t(),
    port: integer(),
    state: :connecting | :handshaking | :connected | :disconnected,
    direction: :outbound | :inbound,
    peer_info: map() | nil,
    node_id: String.t() | nil,
    buffer: binary(),
    local_port: integer() | nil,
    local_node_id: String.t() | nil
  }

  # Client API

  @doc """
  Start an outbound peer connection.
  """
  @spec start_link_outbound(String.t(), integer(), keyword()) :: GenServer.on_start()
  def start_link_outbound(address, port, opts \\ []) do
    init_state = %__MODULE__{
      address: address,
      port: port,
      state: :connecting,
      direction: :outbound,
      buffer: <<>>,
      local_port: Keyword.get(opts, :local_port),
      local_node_id: Keyword.get(opts, :local_node_id)
    }
    GenServer.start_link(__MODULE__, {:outbound, init_state}, opts)
  end

  @doc """
  Start an inbound peer connection with existing socket.
  """
  @spec start_link_inbound(:gen_tcp.socket(), String.t(), integer(), keyword()) :: GenServer.on_start()
  def start_link_inbound(socket, address, port, opts \\ []) do
    init_state = %__MODULE__{
      socket: socket,
      address: address,
      port: port,
      state: :handshaking,
      direction: :inbound,
      buffer: <<>>,
      local_port: Keyword.get(opts, :local_port),
      local_node_id: Keyword.get(opts, :local_node_id)
    }
    GenServer.start_link(__MODULE__, {:inbound, init_state}, opts)
  end

  @doc """
  Send a message to the peer.
  """
  @spec send_message(GenServer.server(), atom(), any()) :: :ok | {:error, term()}
  def send_message(peer, command, payload) do
    GenServer.call(peer, {:send_message, command, payload})
  end

  @doc """
  Get peer status.
  """
  @spec get_status(GenServer.server()) :: map()
  def get_status(peer) do
    GenServer.call(peer, :get_status)
  end

  @doc """
  Disconnect the peer.
  """
  @spec disconnect(GenServer.server()) :: :ok
  def disconnect(peer) do
    GenServer.cast(peer, :disconnect)
  end

  # GenServer Callbacks

  @impl true
  def init({:outbound, state}) do
    Logger.info("🔗 Starting outbound connection ↗️ #{state.address}:#{state.port}")
    send(self(), :connect)
    {:ok, state}
  end

  def init({:inbound, state}) do
    Logger.info("📥 Starting inbound connection ↙️ #{state.address}:#{state.port}")
    # Configure socket for active mode - IMPORTANT: packet mode must match outbound
    case :inet.setopts(state.socket, [:binary, {:active, true}, {:packet, :raw}]) do
      :ok ->
        Logger.info("✅ Socket configured for inbound peer #{state.address}:#{state.port}")
      {:error, reason} ->
        Logger.error("❌ Failed to configure socket: #{inspect(reason)}")
    end
    send(self(), :start_handshake)
    {:ok, state}
  end

  @impl true
  def handle_call({:send_message, command, payload}, _from, %{state: :connected} = state) do
    case send_protobuf_message(state.socket, command, payload) do
      :ok ->
        Logger.debug("📤 Sent #{command} to #{state.address}:#{state.port}")
        {:reply, :ok, state}

      {:error, reason} ->
        Logger.error("❌ Failed to send #{command}: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:send_message, _command, _payload}, _from, state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call(:get_status, _from, state) do
    status = %{
      address: state.address,
      port: state.port,
      state: state.state,
      direction: state.direction,
      peer_info: state.peer_info,
      node_id: state.node_id
    }
    {:reply, status, state}
  end

  @impl true
  def handle_cast(:disconnect, %{socket: nil} = state) do
    Logger.info("👋 Disconnecting from #{state.address}:#{state.port}")
    {:stop, :normal, %{state | state: :disconnected}}
  end

  def handle_cast(:disconnect, %{socket: socket} = state) do
    Logger.info("👋 Disconnecting from #{state.address}:#{state.port}")
    :gen_tcp.close(socket)
    {:stop, :normal, %{state | state: :disconnected, socket: nil}}
  end

  @impl true
    def handle_info(:connect, %{direction: :outbound} = state) do
    case :gen_tcp.connect(String.to_charlist(state.address), state.port,
                         [:binary, {:active, true}, {:packet, :raw}], @connect_timeout) do
      {:ok, socket} ->
        Logger.info("✅ Connected ↗️ #{state.address}:#{state.port}")
        new_state = %{state | socket: socket, state: :handshaking}
        send(self(), :start_handshake)
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("❌ Failed to connect to #{state.address}:#{state.port}: #{inspect(reason)}")
        {:stop, :normal, %{state | state: :disconnected}}
    end
  end

  def handle_info(:start_handshake, %{state: :handshaking} = state) do
    Logger.info("🤝 Starting handshake with #{state.address}:#{state.port} #{arrow_for_direction(state.direction)} #{state.direction}")

    case state.direction do
      :outbound ->
        # Send version message with current blockchain height (fallback to 0 if Chain not available)
        current_height = try do
          Bastille.Features.Chain.Chain.get_height()
        catch
          :exit, _ -> 0
        end
        version_msg = Messages.version_message(
          user_agent: "/Bastille:1.0.0/",
          from_ip: "127.0.0.1",
          from_port: state.local_port || 8333,
          start_height: current_height
        )

        Logger.debug("📝 Version message prepared: #{inspect(version_msg)}")
        case send_protobuf_message(state.socket, :version, version_msg[:version]) do
          :ok ->
            Logger.info("📤 Sent version ↗️ #{state.address}:#{state.port}")
            Process.send_after(self(), :handshake_timeout, @handshake_timeout)
            {:noreply, state}

          {:error, reason} ->
            Logger.error("❌ Failed to send version: #{inspect(reason)}")
            {:stop, :normal, state}
        end

      :inbound ->
        # Wait for incoming version message
        Process.send_after(self(), :handshake_timeout, @handshake_timeout)
        {:noreply, state}
    end
  end

  def handle_info(:handshake_timeout, %{state: :handshaking} = state) do
    Logger.warning("⏰ Handshake timeout with #{state.address}:#{state.port}")
    {:stop, :normal, state}
  end

  # Legacy constant removed; protobuf framing enforces sizes
  @max_frame_bytes 2_000_000

  def handle_info({:tcp, socket, data}, %{socket: socket} = state) do
    # In :raw mode, we may receive arbitrary sized chunks; buffer and process full frames
    buffer = (state.buffer || <<>>) <> data
    case consume_proto_frames(buffer, state) do
      {:ok, new_buffer, new_state} ->
        {:noreply, %{new_state | buffer: new_buffer}}
      {:disconnect, reason} ->
        Logger.warning("🚫 Disconnecting from #{state.address}:#{state.port} due to protocol error: #{inspect(reason)}")
        if state.socket, do: :gen_tcp.close(state.socket)
        {:noreply, %{state | state: :disconnected, socket: nil}}
    end
  end

  def handle_info({:tcp_closed, socket}, %{socket: socket} = state) do
    Logger.info("🔌 Connection closed by #{state.address}:#{state.port}")
    {:stop, :normal, %{state | state: :disconnected, socket: nil}}
  end

  def handle_info({:tcp_error, socket, reason}, %{socket: socket} = state) do
    Logger.error("💥 TCP error with #{state.address}:#{state.port}: #{inspect(reason)}")
    {:stop, :normal, %{state | state: :disconnected, socket: nil}}
  end

  def handle_info(msg, state) do
    Logger.debug("🤷 Unknown message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private functions

  defp process_message(:version, payload, %{state: :handshaking, direction: :inbound} = state) do
    Logger.info("🤝 Received version ↙️ #{state.address}:#{state.port}")

    # Validate network and version payload (chained)
    with :ok <- validate_network(payload),
         :ok <- Validation.validate_message(:version, payload) do
      :ok
    else
      {:error, reason} ->
        Logger.warning("⚠️ Invalid version from #{state.address}:#{state.port}: #{inspect(reason)}")
        return_state = %{state | state: :disconnected}
        Process.send_after(self(), :handshake_timeout, 0)
        return_state
    end

    # Self-connection guard: drop if peer reports our own from_ip/from_port
    if (payload["from_ip"] == "127.0.0.1" or payload["from_ip"] == state.address) and payload["from_port"] == state.local_port do
      Logger.warning("🚫 Detected self-connection on port #{state.local_port}, closing")
      return_state = %{state | state: :disconnected}
      Process.send_after(self(), :handshake_timeout, 0)
      return_state
    end

    # Send version response with current blockchain height (fallback to 0 if Chain not available)
    current_height = try do
      Bastille.Features.Chain.Chain.get_height()
    catch
      :exit, _ -> 0
    end
    version_msg = Messages.version_message(
      user_agent: "/Bastille:1.0.0/",
      from_ip: "127.0.0.1",
      from_port: state.local_port || 8333,
      start_height: current_height
    )

    case send_protobuf_message(state.socket, :version, version_msg[:version]) do
      :ok ->
        # Send verack
        case send_protobuf_message(state.socket, :verack, []) do
          :ok ->
            Logger.info("✅ Handshake complete with #{state.address}:#{state.port}")
            # After handshake, exchange heights
            local_height = try do
              Bastille.Features.Chain.Chain.get_height()
            catch
              :exit, _ -> 0
            end
            height_msg = Bastille.Features.P2P.Messaging.Messages.height_message(local_height)
            _ = send_protobuf_message(state.socket, :height, height_msg[:height])
            %{state | state: :connected, peer_info: payload, node_id: Map.get(payload, "nonce")}

          _ ->
            state
        end

      _ ->
        state
    end
  end

  defp process_message(:version, payload, %{state: :handshaking, direction: :outbound} = state) do
    Logger.info("🤝 Received version ↙️ #{state.address}:#{state.port}")

    # Validate network and version payload (chained)
    with :ok <- validate_network(payload),
         :ok <- Validation.validate_message(:version, payload) do
      :ok
    else
      {:error, reason} ->
        Logger.warning("⚠️ Invalid version from #{state.address}:#{state.port}: #{inspect(reason)}")
        return_state = %{state | state: :disconnected}
        Process.send_after(self(), :handshake_timeout, 0)
        return_state
    end

    # Self-connection guard
    if (payload["from_ip"] == "127.0.0.1" or payload["from_ip"] == state.address) and payload["from_port"] == state.local_port do
      Logger.warning("🚫 Detected self-connection on port #{state.local_port}, closing")
      return_state = %{state | state: :disconnected}
      Process.send_after(self(), :handshake_timeout, 0)
      return_state
    end

    # Send verack
    case send_protobuf_message(state.socket, :verack, []) do
      :ok ->
        Logger.info("✅ Handshake complete with #{state.address}:#{state.port}")
        # After handshake, exchange heights
        local_height = try do
          Bastille.Features.Chain.Chain.get_height()
        catch
          :exit, _ -> 0
        end
        height_msg = Bastille.Features.P2P.Messaging.Messages.height_message(local_height)
        _ = send_protobuf_message(state.socket, :height, height_msg[:height])
        %{state | state: :connected, peer_info: payload, node_id: Map.get(payload, "nonce")}

      _ ->
        state
    end
  end

  defp process_message(:verack, _payload, %{state: :handshaking} = state) do
    direction_arrow = if state.direction == :outbound, do: "↗️", else: "↙️"
    Logger.info("✅ Received verack #{direction_arrow} #{state.address}:#{state.port}")
    %{state | state: :connected}
  end

  defp process_message(:ping, nonce, %{state: :connected} = state) do
    Logger.debug("🏓 Ping from #{state.address}:#{state.port}")
    send_protobuf_message(state.socket, :pong, nonce)
    state
  end

  defp process_message(:pong, _nonce, %{state: :connected} = state) do
    Logger.debug("🏓 Pong from #{state.address}:#{state.port}")
    state
  end

  defp process_message(:height, %{"height" => peer_height}, %{state: :connected} = state) do
    Logger.debug("📏 Height #{peer_height} from #{state.address}:#{state.port}")

    peer_id = "#{state.address}:#{state.port}"
    try do
      Bastille.Features.P2P.Synchronization.Sync.peer_height_discovered(peer_height, peer_id)
    catch
      :exit, _ ->
        Logger.debug("📏 Sync coordinator not available, ignoring height message")
    end

    state
  end

  defp process_message(command, payload, state) do
    Logger.debug("📨 Received #{command} from #{state.address}:#{state.port}")
    # Notify parent process about received message
    notify_node(command, payload, state)
  end

  defp notify_node(command, payload, state) do
    case Process.whereis(Bastille.Features.P2P.PeerManagement.Node) do
      pid when is_pid(pid) ->
        send(pid, {:p2p_message, command, payload, state.address, state.port})
        state
      _ ->
        # Node coordinator not running (e.g., isolated Peer test)
        state
    end
  end

  defp arrow_for_direction(:outbound), do: "↗️"
  defp arrow_for_direction(_), do: "↙️"

  defp send_protobuf_message(socket, command, payload) do
    with {:ok, raw} <- Codec.encode(command, payload) do
      data = <<byte_size(raw)::32, raw::binary>>
      Logger.info("📤 ↗️ #{command}: #{inspect(payload)}")
      case :gen_tcp.send(socket, data) do
        :ok -> :ok
        {:error, reason} = error ->
          Logger.error("❌ TCP send failed: #{inspect(reason)}")
          error
      end
    end
  end

  # Proto framing: 4-byte big-endian length prefix per frame
  defp consume_proto_frames(buffer, _state) when byte_size(buffer) > @max_frame_bytes,
    do: {:disconnect, :frame_too_large}
  defp consume_proto_frames(<<len::32, rest::binary>>, state) when byte_size(rest) >= len do
    <<frame::binary-size(len), tail::binary>> = rest
    case Codec.decode(frame) do
      {:ok, {command, payload}} ->
        Logger.info("📨 ↙️ #{command}: #{inspect(payload)}")
        new_state = process_message(command, payload, state)
        consume_proto_frames(tail, new_state)
      {:error, reason} ->
        Logger.warning("🚫 Protobuf decode error from #{state.address}:#{state.port}: #{inspect(reason)}")
        Logger.debug("🔍 Invalid frame (#{byte_size(frame)} bytes): #{Base.encode16(frame, case: :lower) |> String.slice(0, 100)}...")
        {:disconnect, {:invalid_protobuf_frame, reason}}
    end
  end
  defp consume_proto_frames(buffer, state), do: {:ok, buffer, state}

  defp validate_network(%{} = payload) do
    local_network = Application.get_env(:bastille, :network, :testnet)
    local_magic = Bastille.Features.P2P.Messaging.Messages.get_network_magic(local_network)
    with :ok <- Validation.validate_network(payload, local_network, local_magic),
         :ok <- Validation.validate_version_payload(payload) do
      :ok
    else
      _ -> {:error, :network_mismatch}
    end
  end
  defp validate_network(_), do: {:error, :network_mismatch}
end
