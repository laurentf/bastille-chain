defmodule Bastille.Application do
  @moduledoc """
  The Bastille Application.

  This is the main entry point for the Bastille blockchain system.
  It sets up the supervision tree for all core components following
  the Revolutionary Architecture from PLAN.md.
  """

  use Application

  # New feature-oriented aliases
  alias Bastille.Features.Chain.Chain
  alias Bastille.Features.Mining.{MiningCoordinator, ProofOfWork}
  alias Bastille.Features.Transaction.Mempool
  alias Bastille.Features.Chain.OrphanManager
  alias Bastille.Features.P2P.PeerManagement.Node
  alias Bastille.Features.P2P.Synchronization.Sync
  # BurnTracker removed (burn disabled for now)
  alias Bastille.Features.Api.RPC
  alias Bastille.Infrastructure.Storage.CubDB.{Blocks, State, Index}
  alias Bastille.Infrastructure.Storage.CubDB.Chain, as: ChainStorage
  alias Bastille.Features.Consensus.Engine
  alias Bastille.Features.Tokenomics.CoinbaseMaturity

  @impl true
  def start(_type, _args) do
    # Set storage base path for Rust NIFs to use same path as Elixir
    storage_base_path = Application.get_env(:bastille, :storage_base_path, "data/test")
    System.put_env("BASTILLE_STORAGE_BASE_PATH", storage_base_path)

    # Extract mining configuration with pipeline
    validator_config =
      :bastille
      |> Application.get_env(:mining, [])
      |> build_validator_config()

    # Extract consensus configuration
    consensus_config = build_consensus_config()

    # Extract P2P configuration
    p2p_node_config = build_p2p_config()

    children = [
      RPC,                           # JSON-RPC interface for Bastille
      # 🏰 Revolutionary Supervision Tree (Feature-Oriented Architecture)
      # 🗄️ Modern 4-Database Storage Architecture (CubDB-based)
      {Blocks, []},                  # Time-partitioned block storage (blocks202501.cubdb)
      {ChainStorage, []},            # Chain structure/metadata (chain.cubdb)
      {State, []},                   # Account balances/nonces (state.cubdb)
      {Index, []},                   # Fast lookups/indexes (index.cubdb)

      {CoinbaseMaturity, []},        # Bitcoin-style coinbase maturity system
      {Chain, []},                   # Revolutionary blockchain state
      {Mempool, []},                 # Post-quantum transaction pool
      {OrphanManager, []},           # Orphan block manager (Bitcoin-style)
      {Engine, consensus_config},    # Democratic consensus with proper config
      {MiningCoordinator, validator_config}, # Blake3 mining & validation with config
      {Node, p2p_node_config},       # P2P network node coordinator
      {Sync, []}                     # Blockchain synchronization coordinator
    ]
    |> Enum.filter(&valid_child?/1)

    opts = [strategy: :one_for_one, name: Bastille.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Pipeline helper with pattern matching
  defp build_validator_config(mining_config) do
    [
      mining_enabled: Keyword.get(mining_config, :enabled, false),
      mining_address: Keyword.get(mining_config, :address)
    ]
  end

  defp build_consensus_config do
    consensus_config = Application.get_env(:bastille, :consensus, [])
    module = Keyword.get(consensus_config, :module, ProofOfWork)
    config = Keyword.get(consensus_config, :config, %{})

    [
      consensus_module: module,
      consensus_config: config
    ]
  end

  defp build_p2p_config do
    p2p_config = Application.get_env(:bastille, :p2p, [])

    [
      port: Keyword.get(p2p_config, :listen_port, Keyword.get(p2p_config, :port, 8333)),
      bootstrap_peers: Keyword.get(p2p_config, :bootstrap_peers, [])
    ]
  end

  # Guard for valid children
  defp valid_child?(child) when child != nil, do: true
  defp valid_child?(_), do: false

  @impl true
  def stop(_state) do
    :ok
  end
end
