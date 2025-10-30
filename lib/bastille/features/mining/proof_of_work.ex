defmodule Bastille.Features.Mining.ProofOfWork do
  @moduledoc """
  Simple Bitcoin-like Proof of Work consensus using Blake3 hashing.

  This implementation follows Bitcoin's PoW model but uses Blake3 instead of SHA-256
  for superior performance while maintaining cryptographic security.
  """

  require Logger

  alias Bastille.Features.Block.Block
  alias Bastille.Features.Mining.Mining

  @behaviour Bastille.Features.Consensus.Behaviour

  # Mining parameters - Bitcoin-like but optimized for Blake3
  @batch_size 1_000_000  # Large batch size for Blake3 efficiency

  defstruct [
    :target_block_time,
    :difficulty_adjustment_interval,
    :max_difficulty_change_factor,
    :minimum_difficulty,
    :current_difficulty,
    :max_target
  ]

  @type t :: %__MODULE__{
    target_block_time: pos_integer(),
    difficulty_adjustment_interval: pos_integer(),
    max_difficulty_change_factor: float(),
    minimum_difficulty: pos_integer(),
    current_difficulty: pos_integer(),
    max_target: integer()
  }

  @default_target_block_time 10_000  # 10 seconds target
  @default_difficulty_adjustment_interval 10  # blocks
  @default_max_difficulty_change_factor 4.0
  @default_minimum_difficulty 1
  @default_initial_difficulty 4  # Starting difficulty for Blake3

  @impl true
  def init(config \\ %{}) do
    max_target = Map.get(config, :max_target, 0)

    state = %__MODULE__{
      target_block_time: Map.get(config, :target_block_time, @default_target_block_time),
      difficulty_adjustment_interval: Map.get(config, :difficulty_adjustment_interval, @default_difficulty_adjustment_interval),
      max_difficulty_change_factor: Map.get(config, :max_difficulty_change_factor, @default_max_difficulty_change_factor),
      minimum_difficulty: Map.get(config, :minimum_difficulty, @default_minimum_difficulty),
      current_difficulty: Map.get(config, :initial_difficulty, @default_initial_difficulty),
      max_target: max_target
    }

    target_mode = if max_target > 0, do: "TEST (ultra-easy)", else: "PRODUCTION (real)"
    Logger.info("🔍 Blake3 Proof of Work initialized - #{target_mode} targets")
    {:ok, state}
  end

  @impl true
  def mine_block(%Bastille.Features.Block.Block{header: %{difficulty: block_difficulty}} = block, %__MODULE__{} = state) do
    target = if state.max_target > 0 do
      calculate_configured_target(block_difficulty, state)
    else
      calculate_target(block_difficulty)
    end

    target_type = if state.max_target > 0, do: "TEST", else: "PRODUCTION"
    Logger.info("⚡ Mining block #{block.header.index} with Blake3 - #{target_type} difficulty: #{block_difficulty}")
    mine_block_simple(block, target)
  end

  @impl true
  def validate_block(%Bastille.Features.Block.Block{} = block, %__MODULE__{} = state) do
    if state.max_target > 0 do
      validate_proof_of_work_with_configured_target(block, state)
    else
      validate_proof_of_work(block)
    end
  end

  @impl true
  def update_state(%Bastille.Features.Block.Block{} = _block, %__MODULE__{} = state) do
    {:ok, state}
  end

  @impl true
  def get_difficulty(%__MODULE__{current_difficulty: difficulty}), do: difficulty

  @impl true
  def adjust_difficulty(recent_block_times, %__MODULE__{} = state) when length(recent_block_times) < state.difficulty_adjustment_interval do
    state.current_difficulty
  end

  def adjust_difficulty(recent_block_times, %__MODULE__{} = state) do
    times_for_calculation = Enum.take(recent_block_times, state.difficulty_adjustment_interval)

    if length(times_for_calculation) < state.difficulty_adjustment_interval do
      state.current_difficulty
    else
      actual_time = calculate_actual_time_from_times(times_for_calculation)
      expected_time = state.target_block_time * state.difficulty_adjustment_interval

      time_ratio = actual_time / expected_time
      min_factor = 1 / state.max_difficulty_change_factor
      adjustment_factor = min(state.max_difficulty_change_factor, max(min_factor, time_ratio))

      new_difficulty = round(state.current_difficulty / adjustment_factor)
      max(state.minimum_difficulty, new_difficulty)
    end
  end

  @impl true
  def can_produce_block?(%__MODULE__{}) do
    true
  end

  @impl true
  def info(%__MODULE__{} = state) do
    %{
      consensus_type: "proof_of_work",
      current_difficulty: state.current_difficulty,
      target_block_time: state.target_block_time,
      difficulty_adjustment_interval: state.difficulty_adjustment_interval,
      algorithm: "blake3",
      style: "bitcoin_like",
      performance: "high_speed"
    }
  end

  @spec set_difficulty(%__MODULE__{}, non_neg_integer()) :: %__MODULE__{}
  def set_difficulty(%__MODULE__{} = state, new_difficulty) when is_integer(new_difficulty) and new_difficulty > 0 do
    %{state | current_difficulty: new_difficulty}
  end

  # ===== TESTING FUNCTIONS WITH EASY TARGETS =====

  @doc """
  Mines a block using easy testing targets for fast test execution.
  """
  @spec mine_block_for_test(Block.t(), %__MODULE__{}) :: {:ok, Block.t()} | {:error, term()}
  def mine_block_for_test(%Bastille.Features.Block.Block{header: %{difficulty: block_difficulty}} = block, %__MODULE__{} = state) do
    target = calculate_configured_target(block_difficulty, state)
    Logger.info("⚡ TEST Mining block #{block.header.index} with Blake3 - configured difficulty: #{block_difficulty}")
    mine_block_simple(block, target)
  end

  @doc """
  Validates a block using easy testing targets.
  """
  @spec validate_block_for_test(Block.t(), %__MODULE__{}) :: :ok | {:error, term()}
  def validate_block_for_test(%Bastille.Features.Block.Block{} = block, %__MODULE__{} = state) do
    validate_proof_of_work_with_configured_target(block, state)
  end

  # ===== BITCOIN-LIKE IMPLEMENTATION WITH BLAKE3 =====

  defp validate_proof_of_work(%Bastille.Features.Block.Block{hash: block_hash, header: %{difficulty: difficulty, nonce: nonce}} = block) do
    case block_hash do
      hash when is_binary(hash) and byte_size(hash) == 32 ->
        # Simple validation: recalculate hash and check if it meets target
        block_data = serialize_block_for_mining(block)
        expected_hash = blake3_hash(block_data <> <<nonce::little-64>>)

        cond do
          expected_hash != hash ->
            Logger.warning("Hash mismatch for block #{block.header.index}")
            {:error, :invalid_hash}

          not hash_meets_difficulty?(hash, difficulty) ->
            Logger.warning("Hash doesn't meet difficulty for block #{block.header.index}")
            {:error, :invalid_difficulty}

          true ->
            Logger.debug("Block #{block.header.index} validation successful")
            :ok
        end

      _ ->
        Logger.warning("Invalid block hash format")
        {:error, :missing_hash}
    end
  end

  defp mine_block_simple(block, target_int) do
    block_data = serialize_block_for_mining(block)
    start_time = System.monotonic_time(:millisecond)

    Logger.info("Starting simple Blake3 mining...")

    case find_valid_nonce(block_data, target_int, 0) do
      {:ok, nonce, _hash} ->
        elapsed = System.monotonic_time(:millisecond) - start_time
        hash_rate = if elapsed > 0, do: round(nonce / elapsed * 1000), else: 0

        Logger.info("✅ Mining successful! Nonce: #{nonce}, Time: #{elapsed}ms, Rate: #{hash_rate} H/s")

        # Use Block.calculate_blake3_hash for consistent hashing
        mined_block = %{block |
          header: %{block.header | nonce: nonce}
        }
        |> Block.calculate_blake3_hash()

        {:ok, mined_block}

      {:error, reason} ->
        Logger.error("❌ Mining failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp find_valid_nonce(block_data, target_int, nonce) do
    # Simple incremental nonce search with batching for performance
    find_nonce_batch(block_data, target_int, nonce, @batch_size)
  end

  defp find_nonce_batch(block_data, target_int, start_nonce, batch_size) do
    Enum.reduce_while(start_nonce..(start_nonce + batch_size - 1), nil, fn nonce, _acc ->
      # Create mining data with nonce
      mining_data = block_data <> <<nonce::little-64>>

      # Single Blake3 hash (Bitcoin-like, but with Blake3)
      hash = blake3_hash(mining_data)

      # Check if hash meets target
      if hash_meets_target?(hash, target_int) do
        {:halt, {:ok, nonce, hash}}
      else
        {:cont, nil}
      end
    end)
    |> case do
      {:ok, nonce, hash} -> {:ok, nonce, hash}
      nil -> find_nonce_batch(block_data, target_int, start_nonce + batch_size, batch_size)
    end
  end

  defp blake3_hash(data) do
    # Use centralized hash utility for consistency
    Mining.blake3_hash(data)
  end

  defp hash_meets_target?(hash, target_int) when is_integer(target_int) do
    # Convert target back to binary and use centralized validation
    target_binary = <<target_int::256>>
    Mining.valid_hash?(hash, target_binary)
  end

  defp hash_meets_difficulty?(hash, difficulty) do
    target = calculate_target(difficulty)
    hash_meets_target?(hash, target)
  end

  defp serialize_block_for_mining(%Bastille.Features.Block.Block{} = block) do
    # Use centralized serialization utility for consistency
    Mining.serialize_block_for_mining(block)
  end

  defp calculate_target(difficulty) when is_integer(difficulty) and difficulty > 0 do
    # Use centralized target calculation for consistency (PRODUCTION)
    Mining.difficulty_to_target(difficulty)
    |> :binary.decode_unsigned(:big)
  end

  defp calculate_configured_target(difficulty, %__MODULE__{max_target: max_target}) when max_target > 0 do
    # Use same logic as validation for consistency (TESTING)
    div(max_target, difficulty)
  end

  defp calculate_configured_target(difficulty, _state) do
    # Fallback to standard target calculation for PRODUCTION
    Mining.difficulty_to_target(difficulty)
    |> :binary.decode_unsigned(:big)
  end

  defp validate_proof_of_work_with_configured_target(%Bastille.Features.Block.Block{hash: block_hash, header: %{difficulty: difficulty, nonce: nonce}} = block, %__MODULE__{max_target: max_target}) do
    case block_hash do
      hash when is_binary(hash) and byte_size(hash) == 32 ->
        # Simple validation: recalculate hash and check if it meets configured target
        block_data = serialize_block_for_mining(block)
        expected_hash = blake3_hash(block_data <> <<nonce::little-64>>)

        cond do
          expected_hash != hash ->
            Logger.warning("Hash mismatch for CONFIGURED block #{block.header.index}")
            {:error, :invalid_hash}

          not hash_meets_configured_difficulty?(hash, difficulty, max_target) ->
            Logger.warning("Hash does not meet CONFIGURED difficulty #{difficulty} for block #{block.header.index}")
            {:error, :insufficient_difficulty}

          true ->
            :ok
        end

      _ ->
        Logger.warning("Invalid block hash format")
        {:error, :missing_hash}
    end
  end

  defp hash_meets_configured_difficulty?(hash, difficulty, max_target) do
    # Handle special case: difficulty 0 = no difficulty requirement (genesis/test blocks)
    case difficulty do
      0 -> true  # No difficulty validation for genesis or test blocks
      _ ->
        target_int = div(max_target, difficulty)
        target_binary = <<target_int::256>>
        Mining.valid_hash?(hash, target_binary)
    end
  end

  defp calculate_actual_time_from_times(block_times) do
    sorted_times = Enum.sort_by(block_times, & &1.timestamp)
    oldest_timestamp = List.first(sorted_times).timestamp
    newest_timestamp = List.last(sorted_times).timestamp
    newest_timestamp - oldest_timestamp
  end
end
