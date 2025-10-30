defmodule Bastille do
  @moduledoc """
  Bastille - A Modular Blockchain Implementation in Elixir

  Bastille is a configurable blockchain platform built with Elixir/OTP that features:

  - **🏰 "1789..." Addresses**: Thematic address format honoring the French Revolution
  - **🔒 Post-Quantum Security**: Multi-signature with 2/3 threshold using Dilithium, Falcon, SPHINCS+
  - **🔧 Modular Consensus**: Pluggable consensus mechanisms (PoW, PoS, custom)
  - **⚡ OTP Architecture**: Built with GenServers, Supervisors, and fault tolerance
  - **🌐 P2P Networking**: Distributed node communication
  - **💾 Persistent Storage**: CubDB-based blockchain storage

  ## Quick Start

      # Start the blockchain
      Bastille.start()

      # Generate post-quantum keypair with "1789..." address
      pq_keys = Bastille.generate_keypair()

      # Start mining
      Bastille.start_mining(pq_keys.address)

      # Create quantum-resistant transaction
      {:ok, tx} = Bastille.create_transaction(from_address, to_address, amount, pq_keys)

      # Get blockchain info
      info = Bastille.get_info()

  """

  alias Bastille.Features.Block.Block
  alias Bastille.Shared.{Crypto, CryptoUtils, Seed}
  alias Bastille.Features.Tokenomics.Token
  alias Bastille.Features.Transaction.Transaction
  alias Bastille.Features.Chain.Chain
  alias Bastille.Features.Transaction.Mempool
  alias Bastille.Features.P2P.PeerManagement.Node, as: P2PNode
  alias Bastille.Infrastructure.Storage.CubDB, as: Storage
  alias Bastille.Features.Mining.MiningCoordinator, as: Validator
  alias Bastille.Features.Consensus, as: Consensus

  @doc """
  Starts the Bastille blockchain system.
  """
  @spec start() :: :ok | {:error, term()}
  def start do
    case Application.start(:bastille) do
      :ok -> :ok
      {:error, {:already_started, :bastille}} -> :ok
      error -> error
    end
  end

  @doc """
  Stops the Bastille blockchain system.
  """
  @spec stop() :: :ok | {:error, term()}
  def stop do
    Application.stop(:bastille)
  end

  @doc """
  Gets comprehensive information about the blockchain state.
  """
  @spec get_info() :: map()
  def get_info do
    %{
      chain: get_chain_info(),
      consensus: get_consensus_info(),
      mempool: get_mempool_info(),
      mining: get_mining_info(),
      network: get_network_info(),
      security: get_security_info()
    }
  end

  @doc """
  Gets information about the blockchain chain.
  """
  @spec get_chain_info() :: map()
  def get_chain_info do
    height = Chain.get_height()
    head_block = Chain.get_head_block()

    head_block_display =
      if head_block do
        %{
          header: %{
            index: head_block.header.index,
            timestamp: head_block.header.timestamp,
            nonce: head_block.header.nonce,
            previous_hash: Base.encode16(head_block.header.previous_hash, case: :lower),
            difficulty: head_block.header.difficulty,
            merkle_root: Base.encode16(head_block.header.merkle_root, case: :lower),
            consensus_data: head_block.header.consensus_data
          },
          transactions: Enum.map(head_block.transactions, &Transaction.to_display_map/1),
          hash: Base.encode16(head_block.hash, case: :lower)
        }
      else
        nil
      end

    %{
      height: height,
      head_hash: if(head_block, do: CryptoUtils.to_hex(head_block.hash), else: nil),
      head_block: head_block_display,
      address_format: "1789...",
      signature_scheme: "post_quantum_2_of_3",
      token_economics: %{
        decimals: 14,
        smallest_unit: "juillet",
        max_supply: "infinite",
        current_supply: Token.format_bast(Token.total_supply_at_block(height)),
        block_reward: Token.format_bast(Token.block_reward(height)),
        model: "utility_token",
        theme: "Bastille Day (July 14th)"
      }
    }
  end

  @doc """
  Gets information about the current consensus mechanism.
  """
  @spec get_consensus_info() :: map()
  def get_consensus_info do
    Consensus.Engine.info()
  end

  @doc """
  Gets information about the mempool.
  """
  @spec get_mempool_info() :: map()
  def get_mempool_info do
    %{
      size: Mempool.size(),
      transactions: Mempool.all_transactions() |> Enum.map(&Transaction.to_display_map/1)
    }
  end

  @doc """
  Gets information about mining status.
  """
  @spec get_mining_info() :: map()
  def get_mining_info do
    Validator.mining_status()
  end

  @doc """
  Gets information about the P2P network.
  """
  @spec get_network_info() :: map()
  def get_network_info do
    P2PNode.get_status()
  end

  @doc """
  Gets information about the security features.
  """
  @spec get_security_info() :: map()
  def get_security_info do
    %{
      address_format: "1789... (Bastille thematic)",
      signature_algorithms: ["Dilithium", "Falcon", "SPHINCS+"],
      threshold: "2/3 algorithms must validate",
      quantum_resistant: true,
      cryptographic_primitives: %{
        hash: "Blake3",
        address_encoding: "Base58 with checksum",
        signature_hash: "SHA3-256"
      }
    }
  end

  @doc """
  Generate a new post-quantum keypair with Bastille address.
  """
  @spec generate_keypair() :: map()
  def generate_keypair do
    pq_keys = Crypto.generate_pq_keypair()
    address = Crypto.generate_bastille_address(pq_keys)

    # Store public keys for verification
    Crypto.store_public_keys_from_keypair(pq_keys)

    %{
      address: address,
      dilithium: pq_keys.dilithium,
      falcon: pq_keys.falcon,
      sphincs: pq_keys.sphincs
    }
  end

  @doc """
  Generate address from mnemonic phrase.
  """
  @spec generate_address() :: String.t()
  def generate_address do
    mnemonic = Seed.generate_master_seed()
    pq_keys = keypair_from_mnemonic(mnemonic)
    Crypto.generate_bastille_address(pq_keys)
  end

  @doc """
  Generate keypair from mnemonic phrase.
  """
  @spec keypair_from_mnemonic(String.t()) :: map()
  def keypair_from_mnemonic(mnemonic) do
    {:ok, keys} = Seed.derive_keys_from_seed(mnemonic)

    keypair = %{
      dilithium: keys.dilithium,
      falcon: keys.falcon,
      sphincs: keys.sphincs
    }

    # Store public keys for transaction verification
    address = Crypto.generate_bastille_address(keypair)
    public_keys = %{
      dilithium: keys.dilithium.public,
      falcon: keys.falcon.public,
      sphincs: keys.sphincs.public
    }
    Storage.State.store_public_keys(address, public_keys)

    keypair
  end

  @doc """
  Generate a new mnemonic phrase with address.
  Returns both mnemonic and derived address.
  """
  @spec generate_address_with_mnemonic() :: %{address: String.t(), mnemonic: String.t(), mnemonic_list: [String.t()]}
  def generate_address_with_mnemonic do
    mnemonic = Seed.generate_master_seed()
    pq_keys = keypair_from_mnemonic(mnemonic)
    address = Crypto.generate_bastille_address(pq_keys)
    mnemonic_list = String.split(mnemonic, " ") |> Enum.map(&String.trim/1)

    %{
      address: address,
      mnemonic: mnemonic,
      mnemonic_list: mnemonic_list
    }
  end

  @doc """
  Derive detailed key information from a mnemonic seed.
  Returns comprehensive key data for verification purposes.
  """
  @spec derive_keys_from_seed(String.t()) :: {:ok, map()} | {:error, term()}
  def derive_keys_from_seed(seed) when is_binary(seed) do
    try do
      {:ok, keys} = Seed.derive_keys_from_seed(seed)

      keypair = %{
        dilithium: keys.dilithium,
        falcon: keys.falcon,
        sphincs: keys.sphincs
      }

              address = Crypto.generate_bastille_address(keypair)

      result = %{
        address: address,
        seed: seed,
        keys: %{
          dilithium: %{
            private_key: Base.encode64(keys.dilithium.private),
            public_key: Base.encode64(keys.dilithium.public),
            key_size: %{
              private: byte_size(keys.dilithium.private),
              public: byte_size(keys.dilithium.public)
            }
          },
          falcon: %{
            private_key: Base.encode64(keys.falcon.private),
            public_key: Base.encode64(keys.falcon.public),
            key_size: %{
              private: byte_size(keys.falcon.private),
              public: byte_size(keys.falcon.public)
            }
          },
          sphincs: %{
            private_key: Base.encode64(keys.sphincs.private),
            public_key: Base.encode64(keys.sphincs.public),
            key_size: %{
              private: byte_size(keys.sphincs.private),
              public: byte_size(keys.sphincs.public)
            }
          }
        },
        algorithm_info: %{
          description: "Post-quantum 2/3 threshold signature system",
          algorithms: ["Dilithium2", "Falcon512", "SPHINCS+_SHAKE_128f"],
          security_level: "NIST Level 1 (128-bit quantum security)"
        }
      }

      {:ok, result}
    rescue
      error -> {:error, Exception.message(error)}
    end
  end

  @doc """
  Create a transaction from mnemonic phrase.
  """
  @spec create_transaction_from_mnemonic(String.t(), String.t(), String.t(), non_neg_integer(), keyword()) ::
    {:ok, Transaction.t()} | {:error, term()}
  def create_transaction_from_mnemonic(mnemonic, from_address, to_address, amount, opts \\ []) do
    case keypair_from_mnemonic(mnemonic) do
      pq_keys when is_map(pq_keys) ->
        # Generate address from keys to verify it matches the from_address
        derived_address = Crypto.generate_bastille_address(pq_keys)

        if derived_address == from_address do
          create_transaction(from_address, to_address, amount, pq_keys, opts)
        else
          {:error, :invalid_mnemonic_or_address_mismatch}
        end

      error -> error
    end
  end

  @doc """
  Creates a new post-quantum transaction.
  Amount can be in BAST (float) or juillet (integer).
  """
  @spec create_transaction(
    String.t(),
    String.t(),
    Token.amount_bast() | Token.amount_juillet(),
    Crypto.pq_keypair(),
    keyword()
  ) :: {:ok, Transaction.t()} | {:error, term()}
  def create_transaction(from_address, to_address, amount, pq_keys, opts \\ []) do
    # Convert amount to juillet if needed
    amount_juillet = if is_float(amount) do
      Token.bast_to_juillet(amount)
    else
      amount
    end

    # Calculate fee if not provided (auto-calculate based on data size)
    data = Keyword.get(opts, :data, <<>>)
    fee_juillet = case Keyword.get(opts, :fee) do
      nil -> Token.calculate_fee(byte_size(data), :normal)
      fee when is_float(fee) -> Token.bast_to_juillet(fee)
      fee -> fee
    end

    # Validate addresses
    with :ok <- validate_bastille_address(from_address),
         :ok <- validate_bastille_address(to_address) do

      # Get current nonce for the address
    current_nonce = Chain.get_nonce(from_address)

      # Create transaction
      tx = Transaction.new([
        from: from_address,
        to: to_address,
        amount: amount_juillet,
        fee: fee_juillet,
        nonce: current_nonce + 1,
        data: data,
        signature_type: :post_quantum_2_of_3
      ])

      # Store public keys for verification
      Crypto.store_public_keys_from_keypair(pq_keys)

      # Create and sign transaction
      signed_tx = Transaction.sign(tx, pq_keys)

      {:ok, signed_tx}
    else
      error -> error
    end
  end


  @doc """
  Submits a transaction to the mempool.
  """
  @spec submit_transaction(Transaction.t()) :: :ok | {:error, term()}
  def submit_transaction(%Bastille.Features.Transaction.Transaction{} = tx) do
    case Mempool.add_transaction(tx) do
      :ok ->
        # Broadcast to network
        P2PNode.broadcast_transaction(tx)
        :ok

      error -> error
    end
  end

  @doc """
  Creates and submits a post-quantum transaction in one step.
  """
  @spec send_transaction(String.t(), String.t(), non_neg_integer(), Crypto.pq_keypair(), keyword()) ::
    :ok | {:error, term()}
  def send_transaction(from_address, to_address, amount, pq_keys, opts \\ []) do
    with {:ok, tx} <- create_transaction(from_address, to_address, amount, pq_keys, opts),
         :ok <- submit_transaction(tx) do
      :ok
    else
      error -> error
    end
  end

  @doc """
  Starts mining blocks to the specified "1789..." address.
  """
  @spec start_mining(String.t()) :: :ok | {:error, term()}
  def start_mining(mining_address) do
    case validate_bastille_address(mining_address) do
      :ok -> Validator.start_mining(mining_address)
      error -> error
    end
  end

  @doc """
  Stops mining blocks.
  """
  @spec stop_mining() :: :ok
  def stop_mining do
    Validator.stop_mining()
  end

  @doc """
  Checks if mining is currently active.
  """
  @spec mining?() :: boolean()
  def mining? do
    # Simple implementation - check if validator process is alive and running
    case Process.whereis(:validator_server) do
      nil -> false
      _pid -> true
    end
  rescue
    _ -> false
  end

  @doc """
  Starts mining without an address (generates one).
  """
  @spec start_mining() :: :ok | {:error, term()}
  def start_mining do
    keypair = generate_keypair()
    start_mining(keypair.address)
  end

  @doc """
  Gets performance information about the mining process.
  """
  @spec get_performance_info() :: map()
  def get_performance_info do
    %{
      mining_active: mining?(),
      consensus_info: get_consensus_info(),
      chain_info: get_chain_info(),
      timestamp: System.system_time(:second)
    }
  end

  @doc """
  Mines a single block manually.
  """
  @spec mine_block(String.t()) :: {:ok, Block.t()} | {:error, term()}
  def mine_block(mining_address) do
    case validate_bastille_address(mining_address) do
      :ok -> Validator.mine_block(mining_address)
      error -> error
    end
  end

  @doc """
  Gets the balance of a "1789..." address in juillet (smallest unit).
  """
  @spec get_balance(String.t()) :: Token.amount_juillet()
  def get_balance(address) do
    Chain.get_balance(address)
  end

  @doc """
  Gets the balance of a "1789..." address formatted in BAST.
  """
  @spec get_balance_bast(String.t()) :: String.t()
  def get_balance_bast(address) do
    address
    |> get_balance()
    |> Token.format_bast()
  end

  @doc """
  Gets detailed token economics information.
  """
  @spec get_token_info() :: map()
  def get_token_info do
    Token.economics_info()
  end

  @doc """
  Convert BAST amount to juillet (smallest unit).
  """
  @spec bast_to_juillet(Token.amount_bast()) :: Token.amount_juillet()
  def bast_to_juillet(bast_amount) do
    Token.bast_to_juillet(bast_amount)
  end

  @doc """
  Convert juillet amount to BAST (human-readable).
  """
  @spec juillet_to_bast(Token.amount_juillet()) :: Token.amount_bast()
  def juillet_to_bast(juillet_amount) do
    Token.juillet_to_bast(juillet_amount)
  end

  @doc """
  Format juillet amount as human-readable BAST string.
  """
  @spec format_bast(Token.amount_juillet()) :: String.t()
  def format_bast(juillet_amount) do
    Token.format_bast(juillet_amount)
  end

  @doc """
  Parse BAST string to juillet amount.
  """
  @spec parse_bast(String.t()) :: {:ok, Token.amount_juillet()} | {:error, atom()}
  def parse_bast(bast_string) do
    Token.parse_bast(bast_string)
  end

  @doc """
  Calculate block reward for given height (with halving).
  """
  @spec get_block_reward(non_neg_integer()) :: Token.amount_juillet()
  def get_block_reward(block_height) do
    Token.block_reward(block_height)
  end

  @doc """
  Get total supply at given block height.
  """
  @spec get_total_supply(non_neg_integer()) :: Token.amount_juillet()
  def get_total_supply(block_height) do
    Token.total_supply_at_block(block_height)
  end

  @doc """
  Gets a block by hash.
  """
  @spec get_block(binary()) :: {:ok, Block.t()} | {:error, :not_found}
  def get_block(hash) do
    Chain.get_block(hash)
  end

  @doc """
  Get block by height.
  """
  @spec get_block_by_height(non_neg_integer()) :: Block.t() | nil
  def get_block_by_height(height) do
    case Chain.get_block_hash_at_height(height) do
      {:ok, block_hash} -> Chain.get_block(block_hash)
      {:error, :not_found} -> nil
    end
  end

  @doc """
  Gets a transaction from the mempool.
  """
  @spec get_transaction(binary()) :: {:ok, Transaction.t()} | {:error, :not_found}
  def get_transaction(tx_hash) do
    Mempool.get_transaction(tx_hash)
  end

  @doc """
  Switches the consensus mechanism.
  """
  @spec switch_consensus(module(), map()) :: :ok | {:error, term()}
  def switch_consensus(consensus_module, config \\ %{}) do
    Consensus.Engine.switch_consensus(consensus_module, config)
  end

  @doc """
  Connects to a peer.
  """
  @spec connect_peer(String.t(), pos_integer()) :: :ok | {:error, term()}
  def connect_peer(address, port) do
    P2PNode.connect_peer(address, port)
  end

  @doc """
  Gets the list of connected peers.
  """
  @spec get_peers() :: [map()]
  def get_peers do
    P2PNode.get_peers()
  end

  @doc """
  Gets a block by its hash.
  """
  @spec get_block_by_hash(String.t()) :: {:ok, Block.t()} | {:error, term()}
  def get_block_by_hash(block_hash) do
    # Try to get from storage
    case Storage.Blocks.get_block(block_hash) do
      {:ok, block} -> {:ok, block}
      {:error, :not_found} -> {:error, :block_not_found}
      error -> error
    end
  end


  @doc """
  Validates a transaction with post-quantum or legacy signatures.
  """
  @spec validate_transaction(Transaction.t()) :: :ok | {:error, term()}
  def validate_transaction(%Bastille.Features.Transaction.Transaction{} = tx) do
    Validator.validate_transaction(tx)
  end

  @doc """
  Validates a block.
  """
  @spec validate_block(Block.t()) :: :ok | {:error, term()}
  def validate_block(%Bastille.Features.Block.Block{} = block) do
    Validator.validate_block(block)
  end

  @doc """
  Validates a Bastille "1789..." address format.
  """
  @spec validate_address(String.t()) :: :ok | {:error, term()}
  def validate_address(address) do
    validate_bastille_address(address)
  end

  @doc """
  Gets example addresses and keys for testing.
  """
  @spec get_examples() :: map()
  def get_examples do
    pq_keys = generate_keypair()
    %{
      post_quantum: %{
        address: pq_keys.address,
        keys: pq_keys,
        signature_type: :post_quantum_2_of_3,
        algorithms: ["Dilithium", "Falcon", "SPHINCS+"]
      },
      special_addresses: %{
        genesis: "1789Genesis",
        prefix: "1789",
        format: "1789[base58-encoded-data][checksum]"
      }
    }
  end

  @doc """
  Benchmark address generation performance.
  """
  @spec benchmark_address_performance(pos_integer()) :: map()
  def benchmark_address_performance(count \\ 1000) do
    start_time = System.monotonic_time(:microsecond)

    # Generate many addresses
    addresses = for _ <- 1..count do
      keys = generate_keypair()
      keys.address
    end

    end_time = System.monotonic_time(:microsecond)
    duration_ms = (end_time - start_time) / 1000

    # Verify all addresses start with "1789"
    all_valid = Enum.all?(addresses, &String.starts_with?(&1, "1789"))

    %{
      count: count,
      duration_ms: duration_ms,
      addresses_per_second: count / (duration_ms / 1000),
      all_valid_format: all_valid,
      sample_addresses: Enum.take(addresses, 5)
    }
  end

  @doc """
  Decode Bastille address format.
  """
  @spec decode_address(String.t()) :: {:ok, binary()} | {:error, atom()}
  def decode_address(address) when is_binary(address) do
    prefix = Application.get_env(:bastille, :address_prefix, "1789")

    case String.starts_with?(address, prefix) do
      true ->
        address_part = String.slice(address, String.length(prefix)..-1//1)

        if byte_size(address_part) == 40 do
          case Base.decode16(address_part, case: :lower) do
            {:ok, decoded} -> {:ok, decoded}
            :error -> {:error, :invalid_hex}
          end
        else
          {:error, :invalid_format}
        end

      false ->
        {:error, :invalid_format}
    end
  end
  def decode_address(_), do: {:error, :invalid_format}

  # Private functions

  defp validate_bastille_address(address) when is_binary(address) do
    prefix = Application.get_env(:bastille, :address_prefix, "1789")

    cond do
      address == prefix <> "Genesis" -> :ok  # Special genesis address
      String.starts_with?(address, prefix) ->
        if Crypto.valid_address?(address) do
          :ok
        else
          {:error, :invalid_bastille_address}
        end
      true ->
        {:error, {:invalid_address_format, expected: "#{prefix}...", got: "invalid"}}
    end
  end

  defp validate_bastille_address(_) do
    prefix = Application.get_env(:bastille, :address_prefix, "1789")
    {:error, {:invalid_address_format, expected: "#{prefix}...", got: "invalid"}}
  end
end
