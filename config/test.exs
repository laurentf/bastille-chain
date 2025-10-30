import Config

# Test Configuration for Bastille
# This is the DEFAULT environment configuration

config :bastille,
  network: :testnet,
  # Test address prefix (hex-valid, same length as production)
  address_prefix: "f789",

  # Coinbase maturity configuration
  coinbase_maturity_blocks: 5,  # 5 blocks for test environment

  # RPC API Configuration for tests
  rpc_port: 8332,  # Standard test RPC port

  # Test-specific storage paths (isolated from prod)
  storage: [
    base_path: "data/test",
    node_prefix: nil  # No prefix for single-node tests
  ],

  # Mining disabled by default (can be enabled for testing)
  mining: [
    enabled: true,
    address: "f7899257e171bdf0630deb199897401935b507520268"
    # Note: block_reward is a protocol constant (1789 BAST), not configurable
  ],

  # Consensus configuration (ultra-fast for tests)
  consensus: [
    module: Bastille.Features.Mining.ProofOfWork,
    config: %{
      initial_difficulty: 8,
      target_block_time: 10_000,
      difficulty_adjustment_interval: 3,
      max_difficulty_change_factor: 2.0,
      minimum_difficulty: 1,
      # easier target for test conf
      max_target: 0x00FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
    }
  ],

  # Mempool configuration
  mempool: [
    max_size: 100,   # Smaller for tests
    min_fee: 1
  ],

  # Validator configuration - uses mining config above
  validator: [],

  # P2P isolated for tests (different port)
  p2p: [
    listen_port: 18_333,
    max_peers: 0,
    discovery_enabled: false
  ]

  # Note: Using modern 4-database architecture - no single bastille.cubdb needed

# Logger configuration for tests
config :logger,
  level: String.to_atom(System.get_env("BASTILLE_LOG_LEVEL") || "info"),  # Configurable log level
  compile_time_purge_matching: [
    [level_lower_than: String.to_atom(System.get_env("BASTILLE_LOG_LEVEL") || "info")]
  ]
