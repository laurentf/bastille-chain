defmodule Bastille.Features.Consensus.Behaviour do
  @moduledoc """
  Behaviour for consensus mechanisms.

  This defines the interface that all consensus mechanisms must implement,
  allowing for pluggable consensus algorithms like PoW, PoS, PoA, etc.
  """

  alias Bastille.Features.Block.Block

  @type consensus_state :: any()
  @type validation_result :: :ok | {:error, reason :: term()}
  @type mining_result :: {:ok, Block.t()} | {:error, reason :: term()}

  @doc """
  Initializes the consensus mechanism with configuration.
  """
  @callback init(config :: map()) :: {:ok, consensus_state()} | {:error, term()}

  @doc """
  Validates a block according to the consensus rules.
  """
  @callback validate_block(Block.t(), consensus_state()) :: validation_result()

  @doc """
  Mines/produces a new block.
  Returns the block when mining is complete or an error.
  """
  @callback mine_block(Block.t(), consensus_state()) :: mining_result()

  @doc """
  Updates the consensus state after a block is added to the chain.
  """
  @callback update_state(Block.t(), consensus_state()) :: {:ok, consensus_state()} | {:error, term()}

  @doc """
  Gets the current difficulty for block production.
  """
  @callback get_difficulty(consensus_state()) :: non_neg_integer()

  @doc """
  Adjusts difficulty based on the block time and consensus rules.
  """
  @callback adjust_difficulty([Block.t()], consensus_state()) :: non_neg_integer()

  @doc """
  Determines if this node can produce the next block.
  """
  @callback can_produce_block?(consensus_state()) :: boolean()

  @doc """
  Gets information about the consensus mechanism.
  """
  @callback info(consensus_state()) :: map()

  @doc """
  Cleanup and shutdown the consensus mechanism.
  """
  @callback terminate(reason :: term(), consensus_state()) :: :ok

  @optional_callbacks [terminate: 2]
end
