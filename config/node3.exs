import Config

# Node 3 Configuration - Connects to Multiple Peers
config :bastille,
  network: :testnet,
  # Address prefix for multi-node testing
  address_prefix: "f789",

  # Coinbase maturity configuration for multinode testing
  coinbase_maturity_blocks: 5,  # 5 blocks (same as test - multinode is just better testing)

  # RPC Configuration - unique port per node
  rpc_port: 8103,
  # Storage with node prefix
  storage: [
    base_path: "data/multinode",
    node_prefix: "node3"
  ],

  # P2P Configuration - Connects to both nodes
  p2p: [
    enabled: true,
    listen_port: 8003,
    max_peers: 10,
    bootstrap_peers: [
      {"127.0.0.1", 8001},  # Connect to node1
      {"127.0.0.1", 8002}   # Connect to node2
    ]
  ],

  # Mining enabled on node3 (backup miner)
  mining: [
    enabled: true,
    address: "f7899257e171bdf0630deb199897401935b507520268"
  ],

  # Consensus configuration
  consensus: [
    module: Bastille.Features.Mining.ProofOfWork,
    config: %{
      initial_difficulty: 1,
      target_block_time: 30_000,
      difficulty_adjustment_interval: 5,
      max_difficulty_change_factor: 2.0,
      minimum_difficulty: 1,
      # easier target for test conf
      max_target: 0x00FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
    }
  ]

# Logging
config :logger,
  level: :info,
  format: "[Node3] $time $metadata[$level] $message\n"
