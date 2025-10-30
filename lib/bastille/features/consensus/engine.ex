defmodule Bastille.Features.Consensus.Engine do
  @moduledoc """
  Consensus Engine GenServer.

  Manages the current consensus mechanism and provides a unified interface
  for consensus operations. Supports hot-swapping consensus algorithms.
  """

  use GenServer
  require Logger

  alias Bastille.Features.Block.Block
  alias Bastille.Features.Consensus.{Behaviour}

  defstruct [
    :consensus_module,
    :consensus_state,
    :config
  ]

  @type t :: %__MODULE__{
    consensus_module: module(),
    consensus_state: Behaviour.consensus_state(),
    config: map()
  }

  # Client API

  @doc """
  Starts the consensus engine.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Validates a block using the current consensus mechanism.
  """
  @spec validate_block(Block.t()) :: Behaviour.validation_result()
  def validate_block(%Bastille.Features.Block.Block{} = block) do
    GenServer.call(__MODULE__, {:validate_block, block}, 30_000)
  end

  @doc """
  Mines a block using the current consensus mechanism.
  """
  @spec mine_block(Block.t()) :: Behaviour.mining_result()
  def mine_block(%Bastille.Features.Block.Block{} = block) do
    GenServer.call(__MODULE__, {:mine_block, block}, :infinity)
  end

  @doc """
  Updates the consensus state after a block is added.
  """
  @spec update_state(Block.t()) :: :ok | {:error, term()}
  def update_state(%Bastille.Features.Block.Block{} = block) do
    GenServer.call(__MODULE__, {:update_state, block})
  end

  @doc """
  Gets the current difficulty.
  """
  @spec get_difficulty() :: non_neg_integer()
  def get_difficulty do
    GenServer.call(__MODULE__, :get_difficulty, 5_000)
  end

  @doc """
  Adjusts difficulty based on recent blocks.
  """
  @spec adjust_difficulty([Block.t()]) :: non_neg_integer()
  def adjust_difficulty(recent_blocks) do
    GenServer.call(__MODULE__, {:adjust_difficulty, recent_blocks}, 15_000)
  end

  @doc """
  Adjusts difficulty based on recent block times (lightweight).
  """
  @spec adjust_difficulty_fast([%{index: non_neg_integer(), timestamp: integer()}]) :: non_neg_integer()
  def adjust_difficulty_fast(recent_block_times) do
    GenServer.call(__MODULE__, {:adjust_difficulty_fast, recent_block_times}, 5_000)
  end

  @doc """
  Forces a specific difficulty value (for genesis block or testing).
  """
  @spec set_difficulty(non_neg_integer()) :: :ok
  def set_difficulty(new_difficulty) when is_integer(new_difficulty) and new_difficulty > 0 do
    GenServer.call(__MODULE__, {:set_difficulty, new_difficulty}, 30_000)
  end

  @doc """
  Checks if this node can produce the next block.
  """
  @spec can_produce_block?() :: boolean()
  def can_produce_block? do
    GenServer.call(__MODULE__, :can_produce_block?)
  end

  @doc """
  Gets information about the current consensus mechanism.
  """
  @spec info() :: map()
  def info do
    GenServer.call(__MODULE__, :info)
  end

  @doc """
  Switches to a new consensus mechanism.
  """
  @spec switch_consensus(module(), map()) :: :ok | {:error, term()}
  def switch_consensus(new_module, new_config \\ %{}) do
    GenServer.call(__MODULE__, {:switch_consensus, new_module, new_config})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    consensus_module = Keyword.get(opts, :consensus_module, Bastille.Features.Mining.ProofOfWork)
    consensus_config = Keyword.get(opts, :consensus_config, %{})

    case consensus_module.init(consensus_config) do
      {:ok, consensus_state} ->
        state = %__MODULE__{
          consensus_module: consensus_module,
          consensus_state: consensus_state,
          config: consensus_config
        }

        Logger.info("Consensus engine started with #{inspect(consensus_module)}")
        {:ok, state}

      {:error, reason} ->
        Logger.error("Failed to initialize consensus module #{inspect(consensus_module)}: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:validate_block, block}, _from, %__MODULE__{} = state) do
    result = state.consensus_module.validate_block(block, state.consensus_state)
    {:reply, result, state}
  end

  def handle_call({:mine_block, block}, _from, %__MODULE__{} = state) do
    Logger.debug("Starting block mining with #{inspect(state.consensus_module)}")
    result = state.consensus_module.mine_block(block, state.consensus_state)
    {:reply, result, state}
  end

  def handle_call({:update_state, block}, _from, %__MODULE__{} = state) do
    case state.consensus_module.update_state(block, state.consensus_state) do
      {:ok, new_consensus_state} ->
        new_state = %{state | consensus_state: new_consensus_state}
        {:reply, :ok, new_state}

      {:error, reason} = error ->
        Logger.error("Failed to update consensus state: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  def handle_call(:get_difficulty, _from, %__MODULE__{} = state) do
    difficulty = state.consensus_module.get_difficulty(state.consensus_state)
    {:reply, difficulty, state}
  end

  def handle_call({:adjust_difficulty, recent_blocks}, _from, %__MODULE__{} = state) do
    new_difficulty = state.consensus_module.adjust_difficulty(recent_blocks, state.consensus_state)
    new_state = %{state | consensus_state: maybe_set_difficulty(state, new_difficulty)}
    {:reply, new_difficulty, new_state}
  end

  def handle_call({:adjust_difficulty_fast, recent_block_times}, _from, %__MODULE__{} = state) do
    new_difficulty = state.consensus_module.adjust_difficulty(recent_block_times, state.consensus_state)
    new_state = %{state | consensus_state: maybe_set_difficulty(state, new_difficulty)}
    {:reply, new_difficulty, new_state}
  end

  def handle_call(:can_produce_block?, _from, %__MODULE__{} = state) do
    result = state.consensus_module.can_produce_block?(state.consensus_state)
    {:reply, result, state}
  end

  def handle_call({:set_difficulty, new_difficulty}, _from, %__MODULE__{} = state) do
    new_state = %{state | consensus_state: maybe_set_difficulty(state, new_difficulty)}
    {:reply, :ok, new_state}
  end

  def handle_call(:info, _from, %__MODULE__{} = state) do
    info = state.consensus_module.info(state.consensus_state)
    {:reply, info, state}
  end

  def handle_call({:switch_consensus, new_module, new_config}, _from, %__MODULE__{} = state) do
    Logger.info("Switching consensus from #{inspect(state.consensus_module)} to #{inspect(new_module)}")

    if function_exported?(state.consensus_module, :terminate, 2) do
      state.consensus_module.terminate(:switch, state.consensus_state)
    end

    case new_module.init(new_config) do
      {:ok, new_consensus_state} ->
        new_state = %__MODULE__{
          consensus_module: new_module,
          consensus_state: new_consensus_state,
          config: new_config
        }
        Logger.info("Successfully switched to #{inspect(new_module)}")
        {:reply, :ok, new_state}

      {:error, reason} = error ->
        Logger.error("Failed to switch to #{inspect(new_module)}: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(reason, %__MODULE__{} = state) do
    Logger.info("Consensus engine terminating: #{inspect(reason)}")
    if function_exported?(state.consensus_module, :terminate, 2) do
      state.consensus_module.terminate(reason, state.consensus_state)
    end
    :ok
  end

  defp maybe_set_difficulty(state, new_difficulty) do
    if function_exported?(state.consensus_module, :set_difficulty, 2) do
      state.consensus_module.set_difficulty(state.consensus_state, new_difficulty)
    else
      state.consensus_state
    end
  end
end
