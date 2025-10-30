defmodule Bastille.Features.P2P.Messaging.Codec do
  @moduledoc """
  Protobuf-only wire codec for P2P messages.

  - Uses length-prefixed Envelope (see Bastille.Features.P2P.Messaging.Envelope)
  """

  alias Bastille.P2P.Proto

  @type command ::
          :version | :verack | :inv | :getdata | :block | :tx | :addr | :ping | :pong |
            :getaddr | :getheaders | :headers | :getblocks | :height

  # No wire_format switch; protobuf is the only wire format.

  # --- Encode ---

  @spec encode(command(), any()) :: {:ok, iodata()} | {:error, term()}
  def encode(command, payload), do: encode_proto(command, payload)

  # JSON helpers removed; protobuf-only codec

  defp encode_proto(command, payload) do
    with {:ok, env} <- to_envelope(command, payload) do
      {:ok, Bastille.Features.P2P.Messaging.Envelope.encode(env)}
    end
  rescue
    e -> {:error, {:proto_encode_error, e}}
  end

  # --- Decode ---

  @spec decode(binary()) :: {:ok, {command(), any()}} | {:error, term()}
  def decode(binary), do: decode_proto(binary)

  # JSON helpers removed; protobuf-only codec

  defp decode_proto(frame_binary) do
    case Bastille.Features.P2P.Messaging.Envelope.decode(frame_binary) do
      %Bastille.Features.P2P.Messaging.Envelope{msg: {:version, v}} -> {:ok, {:version, from_version(v)}}
      %Bastille.Features.P2P.Messaging.Envelope{version: v} when not is_nil(v) -> {:ok, {:version, from_version(v)}}
      %Bastille.Features.P2P.Messaging.Envelope{msg: {:verack, _}} -> {:ok, {:verack, []}}
      %Bastille.Features.P2P.Messaging.Envelope{verack: %Proto.Verack{}} -> {:ok, {:verack, []}}
      %Bastille.Features.P2P.Messaging.Envelope{msg: {:ping, %Proto.Ping{nonce: n}}} -> {:ok, {:ping, n}}
      %Bastille.Features.P2P.Messaging.Envelope{ping: %Proto.Ping{nonce: n}} -> {:ok, {:ping, n}}
      %Bastille.Features.P2P.Messaging.Envelope{msg: {:pong, %Proto.Pong{nonce: n}}} -> {:ok, {:pong, n}}
      %Bastille.Features.P2P.Messaging.Envelope{pong: %Proto.Pong{nonce: n}} -> {:ok, {:pong, n}}
      %Bastille.Features.P2P.Messaging.Envelope{msg: {:inv, %Proto.Inv{items: items}}} ->
        {:ok, {:inv, Enum.map(items, &from_inventory_item/1)}}
      %Bastille.Features.P2P.Messaging.Envelope{inv: %Proto.Inv{items: items}} ->
        {:ok, {:inv, Enum.map(items, &from_inventory_item/1)}}
      %Bastille.Features.P2P.Messaging.Envelope{msg: {:getdata, %Proto.GetData{items: items}}} ->
        {:ok, {:getdata, Enum.map(items, &from_inventory_item/1)}}
      %Bastille.Features.P2P.Messaging.Envelope{getdata: %Proto.GetData{items: items}} ->
        {:ok, {:getdata, Enum.map(items, &from_inventory_item/1)}}
      %Bastille.Features.P2P.Messaging.Envelope{msg: {:getheaders, gh}} -> {:ok, {:getheaders, from_getheaders(gh)}}
      %Bastille.Features.P2P.Messaging.Envelope{getheaders: gh} when not is_nil(gh) -> {:ok, {:getheaders, from_getheaders(gh)}}
      %Bastille.Features.P2P.Messaging.Envelope{msg: {:headers, h}} -> {:ok, {:headers, from_headers(h)}}
      %Bastille.Features.P2P.Messaging.Envelope{headers: h} when not is_nil(h) -> {:ok, {:headers, from_headers(h)}}
      %Bastille.Features.P2P.Messaging.Envelope{msg: {:addr, %Proto.Addr{entries: entries}}} ->
        {:ok, {:addr, Enum.map(entries, &from_addr_entry/1)}}
      %Bastille.Features.P2P.Messaging.Envelope{addr: %Proto.Addr{entries: entries}} ->
        {:ok, {:addr, Enum.map(entries, &from_addr_entry/1)}}
      %Bastille.Features.P2P.Messaging.Envelope{msg: {:getblocks, gb}} -> {:ok, {:getblocks, from_getblocks(gb)}}
      %Bastille.Features.P2P.Messaging.Envelope{getblocks: gb} when not is_nil(gb) -> {:ok, {:getblocks, from_getblocks(gb)}}
      %Bastille.Features.P2P.Messaging.Envelope{msg: {:height, %Proto.Height{height: h, timestamp: t}}} ->
        {:ok, {:height, %{"height" => h, "timestamp" => t}}}
      %Bastille.Features.P2P.Messaging.Envelope{height: %Proto.Height{height: h, timestamp: t}} ->
        {:ok, {:height, %{"height" => h, "timestamp" => t}}}
      %Bastille.Features.P2P.Messaging.Envelope{msg: {:block, b}} -> {:ok, {:block, from_block(b)}}
      %Bastille.Features.P2P.Messaging.Envelope{block: b} when not is_nil(b) -> {:ok, {:block, from_block(b)}}
      %Bastille.Features.P2P.Messaging.Envelope{msg: {:tx, t}} -> {:ok, {:tx, from_tx(t)}}
      %Bastille.Features.P2P.Messaging.Envelope{tx: t} when not is_nil(t) -> {:ok, {:tx, from_tx(t)}}
      _ -> {:error, :unknown_envelope}
    end
  rescue
    e -> {:error, {:proto_decode_error, e}}
  end

  # --- Builders (payload -> Envelope) ---

  defp to_envelope(:version, payload) do
    {:ok, %Bastille.Features.P2P.Messaging.Envelope{version: to_version(payload)}}
  end

  defp to_envelope(:verack, _), do: {:ok, %Bastille.Features.P2P.Messaging.Envelope{verack: %Proto.Verack{}}}

  defp to_envelope(:inv, items) do
    proto_items = Enum.map(items, &to_inventory_item/1)
    {:ok, %Bastille.Features.P2P.Messaging.Envelope{inv: %Proto.Inv{items: proto_items}}}
  end

  defp to_envelope(:getdata, items) do
    proto_items = Enum.map(items, &to_inventory_item/1)
    {:ok, %Bastille.Features.P2P.Messaging.Envelope{getdata: %Proto.GetData{items: proto_items}}}
  end

  defp to_envelope(:addr, entries) do
    proto_entries = Enum.map(entries, &to_addr_entry/1)
    {:ok, %Bastille.Features.P2P.Messaging.Envelope{addr: %Proto.Addr{entries: proto_entries}}}
  end

  defp to_envelope(:ping, nonce), do: {:ok, %Bastille.Features.P2P.Messaging.Envelope{ping: %Proto.Ping{nonce: nonce}}}
  defp to_envelope(:pong, nonce), do: {:ok, %Bastille.Features.P2P.Messaging.Envelope{pong: %Proto.Pong{nonce: nonce}}}
  defp to_envelope(:getaddr, _), do: {:ok, %Bastille.Features.P2P.Messaging.Envelope{getaddr: %Proto.GetAddr{}}}

  defp to_envelope(:getheaders, payload) do
    {:ok, %Bastille.Features.P2P.Messaging.Envelope{getheaders: %Proto.GetHeaders{
      version: get_int(payload, ["version", :version], 1),
      hash_count: get_int(payload, ["hash_count", :hash_count], 1),
      block_locator_hashes: get_list(payload, ["block_locator_hashes", :block_locator_hashes], []),
      hash_stop: get_int(payload, ["hash_stop", :hash_stop], 0)
    }}}
  end

  defp to_envelope(:headers, payload) do
    # For now, encode headers as opaque bytes to keep compatibility
    headers = Map.get(payload, :headers) || Map.get(payload, "headers") || []
    bin_headers = Enum.map(headers, &:erlang.term_to_binary/1)
    {:ok, %Bastille.Features.P2P.Messaging.Envelope{headers: %Proto.Headers{count: length(headers), headers: bin_headers}}}
  end

  defp to_envelope(:getblocks, payload) do
    {:ok, %Bastille.Features.P2P.Messaging.Envelope{getblocks: %Proto.GetBlocks{
      version: get_int(payload, ["version", :version], 1),
      start_height: get_int(payload, ["start_height", :start_height], 0),
      stop_height: get_int(payload, ["stop_height", :stop_height], 0),
      max_count: get_int(payload, ["max_count", :max_count], 500)
    }}}
  end

  defp to_envelope(:height, payload) do
    {:ok, %Bastille.Features.P2P.Messaging.Envelope{height: %Proto.Height{
      height: get_int(payload, ["height", :height], 0),
      timestamp: get_int(payload, ["timestamp", :timestamp], System.system_time(:second))
    }}}
  end

  defp to_envelope(:block, payload) do
    {:ok, %Bastille.Features.P2P.Messaging.Envelope{block: to_block(payload)}}
  end

  defp to_envelope(:tx, payload) do
    {:ok, %Bastille.Features.P2P.Messaging.Envelope{tx: to_tx(payload)}}
  end

  defp to_envelope(other, _), do: {:error, {:unsupported_command, other}}

  # --- Conversions to proto types ---

  defp to_version(payload) do
    %Proto.Version{
      network: get_str(payload, ["network", :network], "testnet"),
      magic: get_str(payload, ["magic", :magic], "BASTILLE_TEST_F789"),
      protocol_version: get_int(payload, ["protocol_version", :protocol_version], 1),
      services: get_int(payload, ["services", :services], 1),
      timestamp: get_int(payload, ["timestamp", :timestamp], System.system_time(:second)),
      recv_services: get_int(payload, ["recv_services", :recv_services], 1),
      recv_ip: get_str(payload, ["recv_ip", :recv_ip], "127.0.0.1"),
      recv_port: get_int(payload, ["recv_port", :recv_port], 8333),
      from_services: get_int(payload, ["from_services", :from_services], 1),
      from_ip: get_str(payload, ["from_ip", :from_ip], "127.0.0.1"),
      from_port: get_int(payload, ["from_port", :from_port], 8333),
      nonce: get_int(payload, ["nonce", :nonce], 0),
      user_agent: get_str(payload, ["user_agent", :user_agent], "/Bastille:1.0.0/"),
      start_height: get_int(payload, ["start_height", :start_height], 0),
      relay: get_bool(payload, ["relay", :relay], true)
    }
  end

  defp to_inventory_item(%{"type" => t, "hash" => h}), do: to_inventory_item(%{type: t, hash: h})
  defp to_inventory_item(%{type: t, hash: h}) do
    %Proto.InventoryItem{type: to_item_type(t), hash: h}  # No normalization - keep as-is
  end

  defp to_addr_entry(entry) do
    %Proto.AddrEntry{
      timestamp: get_int(entry, ["timestamp", :timestamp], System.system_time(:second)),
      services: get_int(entry, ["services", :services], 1),
      ip: get_str(entry, ["ip", :ip], "127.0.0.1"),
      port: get_int(entry, ["port", :port], 8333)
    }
  end

  defp to_block(%{"hash" => _} = m), do: to_block(%{hash: m["hash"], header: m["header"], transactions: m["transactions"]})
  defp to_block(%{hash: h, header: header, transactions: txs}) do
    %Proto.Block{
      hash: h,  # Keep hash as-is - no normalization
      header: to_block_header(header),
      transactions: Enum.map(txs || [], &to_tx/1)
    }
  end

  defp to_block_header(header) do
    consensus = header["consensus_data"] || %{}
    %Proto.BlockHeader{
      index: get_int(header, ["index", :index], 0),
      previous_hash: get_any(header, ["previous_hash", :previous_hash], <<0>>),  # No normalization
      timestamp: get_int(header, ["timestamp", :timestamp], 0),
      merkle_root: get_any(header, ["merkle_root", :merkle_root], <<0>>),       # No normalization
      nonce: get_int(header, ["nonce", :nonce], 0),
      difficulty: get_int(header, ["difficulty", :difficulty], 0),
      consensus_data: :erlang.term_to_binary(consensus)
    }
  end

  defp to_tx(%Bastille.Features.Transaction.Transaction{} = tx) do
    %Proto.Transaction{
      from: tx.from,
      to: tx.to,
      amount: tx.amount,
      fee: tx.fee,
      nonce: tx.nonce,
      timestamp: tx.timestamp,
      data: tx.data,
      signature: :erlang.term_to_binary(tx.signature),
      signature_type: to_string(tx.signature_type),
      hash: tx.hash || <<>>
    }
  end
  defp to_tx(%{"from" => _} = m) do
    %Proto.Transaction{
      from: m["from"],
      to: m["to"],
      amount: m["amount"],
      fee: m["fee"],
      nonce: m["nonce"],
      timestamp: m["timestamp"],
      data: m["data"] || <<>>,
      signature: normalize_sig_bytes(m["signature"]),
      signature_type: to_string(m["signature_type"]),
      hash: m["hash"] || <<>>  # No normalization
    }
  end
  defp to_tx(%{from: _} = m), do: to_tx(Map.new(m, fn {k, v} -> {to_string(k), v} end))

  # --- Conversions from proto types ---

  defp from_version(%Proto.Version{} = v) do
    %{
      "network" => v.network,
      "magic" => v.magic,
      "protocol_version" => v.protocol_version,
      "services" => v.services,
      "timestamp" => v.timestamp,
      "recv_services" => v.recv_services,
      "recv_ip" => v.recv_ip,
      "recv_port" => v.recv_port,
      "from_services" => v.from_services,
      "from_ip" => v.from_ip,
      "from_port" => v.from_port,
      "nonce" => v.nonce,
      "user_agent" => v.user_agent,
      "start_height" => v.start_height,
      "relay" => v.relay
    }
  end

  defp from_inventory_item(%Proto.InventoryItem{type: t, hash: h}) do
    %{"type" => from_item_type(t), "hash" => h}  # Keep hash as-is - no encoding
  end

  defp from_addr_entry(%Proto.AddrEntry{} = e) do
    %{"timestamp" => e.timestamp, "services" => e.services, "ip" => e.ip, "port" => e.port}
  end

  defp from_getheaders(%Proto.GetHeaders{} = gh) do
    %{"version" => gh.version, "hash_count" => gh.hash_count, "block_locator_hashes" => gh.block_locator_hashes, "hash_stop" => gh.hash_stop}
  end

  defp from_headers(%Proto.Headers{} = h) do
    decoded = Enum.map(h.headers, fn b -> :erlang.binary_to_term(b) end)
    %{"count" => h.count, "headers" => decoded}
  end

  defp from_getblocks(%Proto.GetBlocks{} = gb) do
    %{"version" => gb.version, "start_height" => gb.start_height, "stop_height" => gb.stop_height, "max_count" => gb.max_count}
  end

  defp from_block(%Proto.Block{} = b) do
    %{
      "hash" => b.hash,
      "header" => from_block_header(b.header),
      "transactions" => Enum.map(b.transactions, &from_tx/1)
    }
  end

  defp from_block_header(%Proto.BlockHeader{} = h) do
    consensus = safe_binary_to_term(h.consensus_data)
    %{
      "index" => h.index,
      "previous_hash" => h.previous_hash,
      "timestamp" => h.timestamp,
      "merkle_root" => h.merkle_root,
      "nonce" => h.nonce,
      "difficulty" => h.difficulty,
      "consensus_data" => consensus
    }
  end

  defp from_tx(%Proto.Transaction{} = t) do
    %{
      "from" => t.from,
      "to" => t.to,
      "amount" => t.amount,
      "fee" => t.fee,
      "nonce" => t.nonce,
      "timestamp" => t.timestamp,
      "data" => t.data,
      "signature" => safe_binary_to_term(t.signature),
      "signature_type" => t.signature_type,
      "hash" => t.hash  # Keep hash as-is - no encoding
    }
  end

  # --- helpers ---
  defp get_any(map, keys, default) do
    Enum.find_value(keys, default, fn k -> Map.get(map, k) end)
  end
  defp get_str(map, keys, default) do
    case get_any(map, keys, default) do
      v when is_binary(v) -> v
      v -> to_string(v)
    end
  end
  defp get_int(map, keys, default) do
    case get_any(map, keys, default) do
      v when is_integer(v) -> v
      v when is_binary(v) -> String.to_integer(v)
      v when is_float(v) -> trunc(v)
      _ -> default
    end
  end
  defp get_bool(map, keys, default) do
    case get_any(map, keys, default) do
      v when is_boolean(v) -> v
      _ -> default
    end
  end
  defp get_list(map, keys, default) do
    case get_any(map, keys, default) do
      v when is_list(v) -> v
      _ -> default
    end
  end

  defp to_item_type(t) when t in ["block", :block], do: 0
  defp to_item_type(t) when t in ["tx", :tx], do: 1
  defp to_item_type(_), do: 1

  defp from_item_type(v) do
    case v do
      0 -> "block"
      1 -> "tx"
      :BLOCK -> "block"
      :TX -> "tx"
      _ -> "tx"
    end
  end

  defp normalize_sig_bytes(nil), do: <<>>
  defp normalize_sig_bytes(bin) when is_binary(bin), do: bin
  defp normalize_sig_bytes(map) when is_map(map), do: :erlang.term_to_binary(map)

  defp safe_binary_to_term(bin) when is_binary(bin) do
    try do
      :erlang.binary_to_term(bin)
    rescue
      _ -> %{}
    end
  end
  defp safe_binary_to_term(_), do: %{}
end
