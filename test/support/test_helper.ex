defmodule Bastille.TestHelper do
  @moduledoc """
  Helper functions for setting up test environment with all necessary services and utilities.
  """

  import ExUnit.Assertions
  import Bitwise

  alias Bastille.Features.Block.Block
  alias Bastille.Shared.Crypto
  alias Bastille.Features.Transaction.Transaction
  alias Bastille.Infrastructure.Storage.CubDB.State

  def start_test_services do
    # Start storage services first
    storage_services = [
      {Bastille.Infrastructure.Storage.CubDB.Blocks, []},
      {Bastille.Infrastructure.Storage.CubDB.Chain, []},
      {Bastille.Infrastructure.Storage.CubDB.Index, []},
      {Bastille.Infrastructure.Storage.CubDB.State, []}
    ]
    
    # Start core blockchain services
    core_services = [
      {Bastille.Features.Chain.Chain, []},
      {Bastille.Features.Transaction.Mempool, []},
      {Bastille.Features.Consensus.Engine, [consensus_module: Bastille.Features.Mining.ProofOfWork]},
      {Bastille.Features.Mining.MiningCoordinator, []}
    ]
    
    # Start all services
    all_services = storage_services ++ core_services
    
    Enum.each(all_services, fn {module, opts} ->
      unless Process.whereis(module) do
        start_supervised!({module, opts})
      end
    end)
    
    # Give services time to initialize
    Process.sleep(100)
    
    :ok
  end
  
  def stop_test_services do
    services = [
      Bastille.Features.Mining.MiningCoordinator,
      Bastille.Features.Consensus.Engine,
      Bastille.Features.Transaction.Mempool,
      Bastille.Features.Chain.Chain,
      Bastille.Infrastructure.Storage.CubDB.State,
      Bastille.Infrastructure.Storage.CubDB.Index,
      Bastille.Infrastructure.Storage.CubDB.Chain,
      Bastille.Infrastructure.Storage.CubDB.Blocks
    ]
    
    Enum.each(services, fn module ->
      if pid = Process.whereis(module) do
        Process.exit(pid, :normal)
      end
    end)
    
    # Give services time to stop
    Process.sleep(100)
    
    :ok
  end
  
  @doc """
  Create a test transaction.
  """
  def create_test_transaction(opts \\ []) do
    defaults = [
      from: "f789testfrom",
      to: "f789testto", 
      amount: 1000,
      fee: 100,
      nonce: 1,
      data: <<>>
    ]

    final_opts = Keyword.merge(defaults, opts)
    Transaction.new(final_opts)
  end

  @doc """
  Generate a test keypair with address.
  """
  def generate_test_keypair do
    pq_keys = Crypto.generate_keypair()
    address = Crypto.generate_bastille_address(pq_keys)
    
    Map.put(pq_keys, :address, address)
  end

  @doc """
  Create a signed transaction for testing.
  """
  def create_signed_transaction(opts \\ []) do
    # Generate keypairs for from and to addresses
    from_keypair = generate_test_keypair()
    to_keypair = generate_test_keypair()

    # Extract only public keys for storage
    from_public_keys = %{
      dilithium: from_keypair.dilithium.public,
      falcon: from_keypair.falcon.public,
      sphincs: from_keypair.sphincs.public
    }
    
    to_public_keys = %{
      dilithium: to_keypair.dilithium.public,
      falcon: to_keypair.falcon.public,
      sphincs: to_keypair.sphincs.public
    }

    # Store public keys in state for validation
    State.store_public_keys(from_keypair.address, from_public_keys)
    State.store_public_keys(to_keypair.address, to_public_keys)

    default_opts = [
      from: from_keypair.address,
      to: to_keypair.address,
      amount: 1000,
      nonce: 1,
      data: ""
    ]

    final_opts = Keyword.merge(default_opts, opts)
    
    # Create transaction
    tx = Transaction.new(final_opts)
    
    # Sign the transaction
    Transaction.sign(tx, from_keypair)
  end

  @doc """
  Create a test block.
  """
  def create_test_block(opts \\ []) do
    transactions = Keyword.get(opts, :transactions, [create_test_transaction()])
    index = Keyword.get(opts, :index, 0)
    _miner_address = Keyword.get(opts, :miner_address, "f789testminer")

    Block.new([
      index: index,
      transactions: transactions,
      previous_hash: <<0::256>>,
      timestamp: System.system_time(:second),
      nonce: 0,
      difficulty: 1
    ])
  end

  @doc """
  Assert a block is valid.
  """
  def assert_valid_block(block) do
    assert Block.valid?(block)
  end

  @doc """
  Assert a transaction is valid.
  """
  def assert_valid_transaction(transaction) do
    assert Transaction.valid?(transaction)
  end

  @doc """
  Count bits in a binary (replacement for Integer.popcount).
  """
  def count_bits(binary) when is_binary(binary) do
    binary
    |> :binary.bin_to_list()
    |> Enum.reduce(0, fn byte, acc ->
      acc + count_bits_in_byte(byte)
    end)
  end

  @doc """
  Clear deterministic cache for clean test state.
  """
  def clear_deterministic_cache do
    Crypto.clear_deterministic_keys_cache()
  end

  @doc """
  Clean up test databases to ensure fresh state.
  """
  def cleanup_test_databases do
    test_data_path = Application.get_env(:bastille, :storage_base_path, "test_data")

    if File.exists?(test_data_path) do
      File.rm_rf!(test_data_path)
    end

    # Also clean up any stray development databases that might conflict
    if File.exists?("data") do
      File.rm_rf!("data")
    end

    :ok
  end
  
  # Private helper functions
  defp start_supervised!(child_spec) do
    case ExUnit.Callbacks.start_supervised(child_spec) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      other -> other
    end
  end

  defp count_bits_in_byte(0), do: 0
  defp count_bits_in_byte(byte) do
    1 + count_bits_in_byte(byte &&& (byte - 1))
  end
end
