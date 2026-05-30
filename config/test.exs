import Config

# Test Configuration for Bastille
# This is the DEFAULT environment configuration

config :bastille,
  network: :testnet,
  # Test address prefix (hex-valid, same length as production)
  address_prefix: "f789",

  # RPC API Configuration for tests
  # Standard test RPC port
  rpc_port: 8332,

  # Test-specific storage paths (isolated from prod)
  storage: [
    base_path: "data/test",
    # No prefix for single-node tests
    node_prefix: nil
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
    # Smaller for tests
    max_size: 100,
    min_fee: 1
  ],

  # Mempool runtime options applied by the supervisor. In tests we skip
  # signature and chain validation so unit tests can add hand-crafted
  # transactions without going through full post-quantum signing. A test
  # that wants real validation can still call Mempool.start_link with
  # explicit opts after stopping the supervised instance.
  mempool_opts: [skip_signature_validation: true, skip_chain_validation: true],

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
  # Configurable log level
  level: String.to_atom(System.get_env("BASTILLE_LOG_LEVEL") || "info"),
  compile_time_purge_matching: [
    [level_lower_than: String.to_atom(System.get_env("BASTILLE_LOG_LEVEL") || "info")]
  ]
