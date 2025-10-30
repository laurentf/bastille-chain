import Config

# Node 1 Configuration - Bootstrap Node
config :bastille,
  network: :testnet,
  # Address prefix for multi-node testing
  address_prefix: "f789",

  # Coinbase maturity configuration for multinode testing
  coinbase_maturity_blocks: 5,  # 5 blocks (same as test - multinode is just better testing)

  # RPC Configuration - unique port per node
  rpc_port: 8101,
  # Storage with node prefix
  storage: [
    base_path: "data/multinode",
    node_prefix: "node1"
  ],

  # P2P Configuration - Bootstrap node
  p2p: [
    enabled: true,
    listen_port: 8001,
    max_peers: 10,
    bootstrap_peers: []  # This is the bootstrap node
  ],

  # Mining enabled on node1
  mining: [
    enabled: true,
    address: "f7899257e171bdf0630deb199897401935b507520268"
  ],

  # Consensus configuration
  consensus: [
    module: Bastille.Features.Mining.ProofOfWork,
    config: %{
      initial_difficulty: 1,  # Easy for testing
      target_block_time: 30_000,  # 30 seconds
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
  format: "[Node1] $time $metadata[$level] $message\n"
