import Config

# Bastille Blockchain Configuration
# Default environment is :test
# Available environments: :test, :prod

config :bastille,
  # Explicit network identifier (used in P2P version handshake)
  network: :testnet,
  # Address prefix configuration
  address_prefix: "f789",  # Default test prefix (hex-valid, same length as prod "1789")

  # RPC API Configuration
  rpc_port: 8332,  # Default RPC port (can be overridden per environment)

  # Enable the REST API
  enable_api: false,

  # Mining configuration - disabled by default
  mining: [
    enabled: false,
    address: nil  # Set this to enable auto-mining
    # Note: block_reward is a protocol constant (1789 BAST), not configurable
  ],

  # Consensus configuration
  consensus: [
    module: Bastille.Features.Mining.ProofOfWork,
    config: %{
      initial_difficulty: 4,
      target_block_time: 10_000,  # 10 seconds
      difficulty_adjustment_interval: 10,  # blocks
      max_difficulty_change_factor: 4.0,
      minimum_difficulty: 1
    }
  ],

  # Mempool configuration
  mempool: [
    max_size: 1000,
    min_fee: 1
  ],

  # Validator configuration - uses mining config above
  validator: [],

  # P2P Network configuration
  p2p: [
    enabled: true,
    port: 8333,
    max_peers: 10,
    discovery_enabled: true,
    bootstrap_peers: []
  ],

  # Storage configuration - test paths by default
  storage: [
    base_path: "data/test",
    node_prefix: nil  # Optional prefix for multi-node setups (e.g., "node1", "node2")
  ]
  # Note: Using 4-database architecture (blocks, chain, state, index) - no single bastille.cubdb

# Environment-specific configuration
config :logger,
  level: :info,
  compile_time_purge_matching: [
    [level_lower_than: :info]
  ]

# Import environment specific config
# Supports: test, prod, and multi-node (node1, node2, node3)
case Mix.env() do
  :test -> import_config "test.exs"
  :prod -> import_config "prod.exs"
  :node1 -> import_config "node1.exs"
  :node2 -> import_config "node2.exs"
  :node3 -> import_config "node3.exs"
  _ -> import_config "test.exs"  # Default to test
end
