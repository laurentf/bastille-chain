import Config

# Node 2 Configuration - Connects to Node 1
config :bastille,
  network: :testnet,
  # Address prefix for multi-node testing
  address_prefix: "f789",

  # Coinbase maturity configuration for multinode testing
  coinbase_maturity_blocks: 5,  # 5 blocks (same as test - multinode is just better testing)

  # RPC Configuration - unique port per node
  rpc_port: 8102,
  # Storage with node prefix
  storage: [
    base_path: "data/multinode",
    node_prefix: "node2"
  ],

  # P2P Configuration - Connects to node1
  p2p: [
    enabled: true,
    listen_port: 8002,
    max_peers: 10,
    bootstrap_peers: [{"127.0.0.1", 8001}]  # Connect to node1
  ],

  # Mining disabled on node2 (pure relay)
  mining: [
    enabled: false
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
      # MUST match Node1's max_target for consistent validation
      max_target: 0x00FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
    }
  ]

# Logging
config :logger,
  level: :info,
  format: "[Node2] $time $metadata[$level] $message\n"
