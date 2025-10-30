defmodule Bastille.Features.Mining.Mining do
  @moduledoc """
  Core mining operations for the Bastille blockchain.

  This module provides the essential mining and block processing functions:
  - Block serialization for mining and validation
  - Blake3 hashing for Proof-of-Work
  - Mining difficulty validation
  - Block hash calculation and verification

  All mining and validation operations should use these functions
  to ensure consistency across the mining system.
  """

  alias Bastille.Features.Block.Block
  alias Bastille.Features.Transaction.Transaction

  @doc """
  Serializes a block for mining operations.

  This is the canonical serialization used for both mining and validation
  to ensure hash consistency.
  """
  @spec serialize_block_for_mining(Block.t()) :: binary()
  def serialize_block_for_mining(%Bastille.Features.Block.Block{header: header, transactions: transactions}) do
    # Bitcoin-like serialization compatible with existing implementation
    header_data = [
      <<header.index::32>>,
      header.previous_hash,
      header.merkle_root,
      <<header.timestamp::64>>,
      <<header.difficulty::32>>
    ] |> IO.iodata_to_binary()

    # Simple transaction serialization
    tx_data = transactions
    |> Enum.map(&Transaction.to_binary/1)
    |> IO.iodata_to_binary()

    header_data <> tx_data
  end


  @doc """
  Performs a single Blake3 hash on data.

  This is the canonical Blake3 hashing implementation used throughout
  the Bastille blockchain for mining and validation.

  Blake3's collision resistance and speed make a single hash sufficient
  for Proof of Work, unlike Bitcoin's double SHA-256.

  ## Examples

      iex> Mining.blake3_hash("test data")
      <<...32 bytes...>>
  """
  @spec blake3_hash(binary()) :: binary()
  def blake3_hash(data) when is_binary(data), do: Bastille.Infrastructure.Crypto.CryptoNif.blake3_hash(data)

  # Alias for backward compatibility
  @spec blake3_double_hash(binary()) :: binary()
  def blake3_double_hash(data), do: blake3_hash(data)

  @doc """
  Calculates the Blake3 hash for a block using canonical serialization.

  This function combines block serialization and single hashing
  to provide the definitive block hash calculation.

  IMPORTANT: This must match exactly the mining logic:
  1. Serialize block WITHOUT nonce
  2. Append nonce as little-endian 64-bit
  3. Single Blake3 hash for security
  """
  @spec calculate_block_hash(Block.t()) :: binary()
  def calculate_block_hash(%Bastille.Features.Block.Block{header: %{nonce: nonce}} = block) do
    # Step 1: Serialize block without nonce (like mining does)
    block_without_nonce = put_in(block.header.nonce, 0)
    block_data = serialize_block_for_mining(block_without_nonce)

    # Step 2: Append nonce as little-endian 64-bit (like mining does)
    mining_data = block_data <> <<nonce::little-64>>

    # Step 3: Single Blake3 hash for security
    blake3_hash(mining_data)
  end

  @doc """
  Validates if a hash meets the difficulty target.

  ## Parameters
  - `hash`: The hash to validate (32 bytes)
  - `target`: The difficulty target (32 bytes, big-endian)

  ## Returns
  - `true` if hash <= target
  - `false` otherwise
  """
  @spec valid_hash?(binary(), binary()) :: boolean()
  def valid_hash?(hash, target) when byte_size(hash) == 32 and byte_size(target) == 32 do
    # Compare as big-endian integers
    hash <= target
  end

  def valid_hash?(_, _), do: false

  @doc """
  Converts difficulty to target value - PRODUCTION mode.

  Uses Bitcoin-like difficulty scaling for real mining with single Blake3.
  """
  @spec difficulty_to_target(non_neg_integer()) :: binary()
  def difficulty_to_target(difficulty) when difficulty >= 0 do
    if difficulty == 0 do
      # Maximum target for genesis
      <<0xFF::256>>
    else
      # Bitcoin-like target calculation for single Blake3
      bitcoin_max_target = 0x0000000FFFF00000000000000000000000000000000000000000000000000000
      target_int = div(bitcoin_max_target, difficulty)
      <<target_int::256>>
    end
  end

  @doc """
  Converts difficulty to target value - TESTING mode.

  Uses ultra-easy targets for fast test execution with single Blake3.
  """
  @spec difficulty_to_test_target(non_neg_integer()) :: binary()
  def difficulty_to_test_target(difficulty) when difficulty >= 0 do
    if difficulty == 0 do
      # Maximum target for genesis or testing
      <<0xFF::256>>
    else
      # Ultra-easy target for testing Blake3 mining
      testing_max_target = 0x00FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
      target_int = div(testing_max_target, difficulty)
      <<target_int::256>>
    end
  end

  @doc """
  Creates an ultra-easy testing target for development.

  This target makes mining almost instant for testing purposes.
  """
  @spec testing_target() :: binary()
  def testing_target do
    # Very high target = very easy mining
    <<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
      0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
      0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
      0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF>>
  end

  @doc """
  Formats a hash for display (first 8 hex characters).
  """
  @spec format_hash(binary()) :: String.t()
  def format_hash(hash) when is_binary(hash) do
    hash
    |> Base.encode16(case: :lower)
    |> String.slice(0, 8)
  end

  @doc """
  Validates block hash consistency.

  Recalculates the block hash and compares with stored hash.
  Returns :ok if consistent, {:error, reason} if not.
  """
  @spec validate_block_hash_consistency(Block.t()) :: :ok | {:error, atom()}
  def validate_block_hash_consistency(%Bastille.Features.Block.Block{hash: nil}), do: {:error, :no_hash}

  def validate_block_hash_consistency(%Bastille.Features.Block.Block{hash: stored_hash} = block) do
    calculated_hash = calculate_block_hash(block)

    if calculated_hash == stored_hash do
      :ok
    else
      {:error, :hash_mismatch}
    end
  end
end
