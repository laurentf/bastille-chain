defmodule Bastille.P2P.Proto.ItemType do
  @moduledoc false
  use Protobuf, enum: true, syntax: :proto3
  field :BLOCK, 0
  field :TX, 1
end

defmodule Bastille.P2P.Proto.InventoryItem do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :type, 1, type: Bastille.P2P.Proto.ItemType, enum: true
  field :hash, 2, type: :bytes
end

defmodule Bastille.P2P.Proto.AddrEntry do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :timestamp, 1, type: :uint64
  field :services, 2, type: :uint64
  field :ip, 3, type: :string
  field :port, 4, type: :uint32
end

defmodule Bastille.P2P.Proto.Version do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :network, 1, type: :string
  field :magic, 2, type: :string
  field :protocol_version, 3, type: :uint32
  field :services, 4, type: :uint64
  field :timestamp, 5, type: :uint64
  field :recv_services, 6, type: :uint64
  field :recv_ip, 7, type: :string
  field :recv_port, 8, type: :uint32
  field :from_services, 9, type: :uint64
  field :from_ip, 10, type: :string
  field :from_port, 11, type: :uint32
  field :nonce, 12, type: :uint64
  field :user_agent, 13, type: :string
  field :start_height, 14, type: :uint64
  field :relay, 15, type: :bool
end

defmodule Bastille.P2P.Proto.Verack do
  @moduledoc false
  use Protobuf, syntax: :proto3
end

defmodule Bastille.P2P.Proto.Inv do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :items, 1, repeated: true, type: Bastille.P2P.Proto.InventoryItem
end

defmodule Bastille.P2P.Proto.GetData do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :items, 1, repeated: true, type: Bastille.P2P.Proto.InventoryItem
end

defmodule Bastille.P2P.Proto.Addr do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :entries, 1, repeated: true, type: Bastille.P2P.Proto.AddrEntry
end

defmodule Bastille.P2P.Proto.Ping do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :nonce, 1, type: :uint64
end

defmodule Bastille.P2P.Proto.Pong do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :nonce, 1, type: :uint64
end

defmodule Bastille.P2P.Proto.GetAddr do
  @moduledoc false
  use Protobuf, syntax: :proto3
end

defmodule Bastille.P2P.Proto.GetHeaders do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :version, 1, type: :uint32
  field :hash_count, 2, type: :uint32
  field :block_locator_hashes, 3, repeated: true, type: :uint64
  field :hash_stop, 4, type: :uint64
end

defmodule Bastille.P2P.Proto.Headers do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :count, 1, type: :uint32
  field :headers, 2, repeated: true, type: :bytes
end

defmodule Bastille.P2P.Proto.BlockHeader do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :index, 1, type: :uint64
  field :previous_hash, 2, type: :bytes
  field :timestamp, 3, type: :uint64
  field :merkle_root, 4, type: :bytes
  field :nonce, 5, type: :uint64
  field :difficulty, 6, type: :uint32
  field :consensus_data, 7, type: :bytes
end

defmodule Bastille.P2P.Proto.Transaction do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :from, 1, type: :string
  field :to, 2, type: :string
  field :amount, 3, type: :uint64
  field :fee, 4, type: :uint64
  field :nonce, 5, type: :uint64
  field :timestamp, 6, type: :uint64
  field :data, 7, type: :bytes
  field :signature, 8, type: :bytes
  field :signature_type, 9, type: :string
  field :hash, 10, type: :bytes
end

defmodule Bastille.P2P.Proto.Block do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :hash, 1, type: :bytes
  field :header, 2, type: Bastille.P2P.Proto.BlockHeader
  field :transactions, 3, repeated: true, type: Bastille.P2P.Proto.Transaction
end

defmodule Bastille.P2P.Proto.GetBlocks do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :version, 1, type: :uint32
  field :start_height, 2, type: :uint64
  field :stop_height, 3, type: :uint64
  field :max_count, 4, type: :uint32
end

defmodule Bastille.P2P.Proto.Height do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :height, 1, type: :uint64
  field :timestamp, 2, type: :uint64
end

defmodule Bastille.Features.P2P.Messaging.Envelope do
  @moduledoc false
  use Protobuf, syntax: :proto3

  oneof :msg do
    field :version, 1, type: Bastille.P2P.Proto.Version
    field :verack, 2, type: Bastille.P2P.Proto.Verack
    field :inv, 3, type: Bastille.P2P.Proto.Inv
    field :getdata, 4, type: Bastille.P2P.Proto.GetData
    field :block, 5, type: Bastille.P2P.Proto.Block
    field :tx, 6, type: Bastille.P2P.Proto.Transaction
    field :addr, 7, type: Bastille.P2P.Proto.Addr
    field :ping, 8, type: Bastille.P2P.Proto.Ping
    field :pong, 9, type: Bastille.P2P.Proto.Pong
    field :getaddr, 10, type: Bastille.P2P.Proto.GetAddr
    field :getheaders, 11, type: Bastille.P2P.Proto.GetHeaders
    field :headers, 12, type: Bastille.P2P.Proto.Headers
    field :getblocks, 13, type: Bastille.P2P.Proto.GetBlocks
    field :height, 14, type: Bastille.P2P.Proto.Height
  end
end
