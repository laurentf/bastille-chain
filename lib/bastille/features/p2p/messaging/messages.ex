defmodule Bastille.Features.P2P.Messaging.Messages do
  @moduledoc """
  Message type definitions for Bastille P2P protocol.

  Based on Bitcoin protocol but adapted for Bastille blockchain.
  """

  @type message_type :: :version | :verack | :inv | :getdata | :block | :tx | :addr | :ping | :pong | :getaddr

  @doc """
  Create a version message.
  """
  @spec version_message(keyword()) :: %{version: map()}
  def version_message(opts \\ []) do
    network = Application.get_env(:bastille, :network, :testnet)
    %{version: %{
      network: to_string(network),
      magic: get_network_magic(network),
      protocol_version: Keyword.get(opts, :protocol_version, 1),
      services: Keyword.get(opts, :services, 1),  # 1 = full node
      timestamp: Keyword.get(opts, :timestamp, System.system_time(:second)),
      recv_services: Keyword.get(opts, :recv_services, 1),
      recv_ip: Keyword.get(opts, :recv_ip, "127.0.0.1"),
      recv_port: Keyword.get(opts, :recv_port, 8333),
      from_services: Keyword.get(opts, :from_services, 1),
      from_ip: Keyword.get(opts, :from_ip, "127.0.0.1"),
      from_port: Keyword.get(opts, :from_port, 8333),
      nonce: Keyword.get(opts, :nonce, :rand.uniform(0xFFFFFFFFFFFFFFFF)),
      user_agent: Keyword.get(opts, :user_agent, "/Bastille:1.0.0/"),
      start_height: Keyword.get(opts, :start_height, 0),
      relay: Keyword.get(opts, :relay, true)
    }}
  end

  @doc false
  @spec get_network_magic(atom()) :: String.t()
  def get_network_magic(:mainnet), do: "BASTILLE_MAIN_1789"
  def get_network_magic(:testnet), do: "BASTILLE_TEST_F789"

  @doc """
  Create a verack message (empty payload).
  """
  @spec verack_message() :: %{verack: []}
  def verack_message, do: %{verack: []}

  @doc """
  Create an inventory message.
  """
  @spec inv_message([{:block | :tx, binary()}]) :: %{inv: list()}
  def inv_message(items) do
    inv_items = Enum.map(items, fn {type, hash} ->
      %{type: type, hash: hash}  # Keep hash as binary - no encoding!
    end)
    %{inv: inv_items}
  end

  @doc """
  Create a getdata message.
  """
  @spec getdata_message([{:block | :tx, binary()}]) :: %{getdata: list()}
  def getdata_message(items) do
    getdata_items = Enum.map(items, fn {type, hash} ->
      %{type: type, hash: hash}  # Keep hash as binary - no encoding!
    end)
    %{getdata: getdata_items}
  end

  @doc """
  Create a block message.
  """
  @spec block_message(Bastille.Features.Block.Block.t()) :: %{block: map()}
  def block_message(%Bastille.Features.Block.Block{} = block) do
    %{block: %{
      hash: block.hash,  # Keep hash as binary - no encoding!
      header: block.header,
      transactions: block.transactions
    }}
  end

  @doc """
  Create a transaction message.
  """
  @spec tx_message(Bastille.Features.Transaction.Transaction.t()) :: %{tx: map()}
  def tx_message(%Bastille.Features.Transaction.Transaction{} = tx) do
    %{tx: %{
      hash: tx.hash,  # Keep hash as binary - no encoding!
      from: tx.from,
      to: tx.to,
      amount: tx.amount,
      fee: tx.fee,
      nonce: tx.nonce,
      timestamp: tx.timestamp,
      signature: tx.signature,
      signature_type: tx.signature_type
    }}
  end

  @doc """
  Create an addr message.
  """
  @spec addr_message([{String.t(), integer()}]) :: %{addr: list()}
  def addr_message(addresses) do
    addr_items = Enum.map(addresses, fn {ip, port} ->
      %{
        timestamp: System.system_time(:second),
        services: 1,  # Full node
        ip: ip,
        port: port
      }
    end)
    %{addr: addr_items}
  end

  @doc """
  Create a ping message.
  """
  @spec ping_message(integer()) :: %{ping: integer()}
  def ping_message(nonce \\ nil) do
    nonce = nonce || :rand.uniform(0xFFFFFFFFFFFFFFFF)
    %{ping: nonce}
  end

  @doc """
  Create a pong message.
  """
  @spec pong_message(integer()) :: %{pong: integer()}
  def pong_message(nonce) do
    %{pong: nonce}
  end

  @doc """
  Create a getaddr message (request peer addresses).
  """
  @spec getaddr_message() :: %{getaddr: []}
  def getaddr_message, do: %{getaddr: []}

  @doc """
  Get the command name from a message.
  """
  @spec get_command(map()) :: atom() | nil
  def get_command(message) when is_map(message) do
    case Map.keys(message) do
      [command] when is_atom(command) -> command
      _ -> nil
    end
  end

  @doc """
  Get the payload from a message.
  """
  @spec get_payload(map()) :: any()
  def get_payload(message) when is_map(message) do
    case Map.values(message) do
      [payload] -> payload
      _ -> nil
    end
  end

  # Blockchain Synchronization Messages

  @doc """
  Create a getheaders message for blockchain sync.
  """
  @spec getheaders_message(integer(), integer()) :: %{getheaders: map()}
  def getheaders_message(start_height, stop_hash \\ 0) do
    %{getheaders: %{
      version: 1,
      hash_count: 1,
      block_locator_hashes: [start_height],  # Simplified: use height instead of hash
      hash_stop: stop_hash
    }}
  end

  @doc """
  Create a headers message response.
  """
  @spec headers_message([map()]) :: %{headers: map()}
  def headers_message(headers) do
    %{headers: %{
      count: length(headers),
      headers: headers
    }}
  end

  @doc """
  Create a getblocks message for requesting specific blocks.
  """
  @spec getblocks_message(integer(), integer(), integer()) :: %{getblocks: map()}
  def getblocks_message(start_height, stop_height, max_count \\ 500) do
    %{getblocks: %{
      version: 1,
      start_height: start_height,
      stop_height: stop_height,
      max_count: max_count
    }}
  end

  @doc """
  Create a height message to advertise current blockchain height.
  """
  @spec height_message(integer()) :: %{height: map()}
  def height_message(current_height) do
    %{height: %{
      height: current_height,
      timestamp: System.system_time(:second)
    }}
  end
end
