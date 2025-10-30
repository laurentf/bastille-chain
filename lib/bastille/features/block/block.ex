defmodule Bastille.Features.Block.Block do
  @moduledoc """
  Core Block data structure and operations.

  Represents a block in the blockchain with  defp calculate_genesis_hash(block) do
    # Calculate a deterministic genesis hash
    # This ensures the genesis hash is always the same
    block_data = serialize_for_hash(block)

    # Simple hash calculation for genesis
    :crypto.hash(:sha256, block_data)
  endransaction data.
  """

  alias Bastille.Shared.CryptoUtils
  alias Bastille.Features.Mining.Mining
  alias Bastille.Features.Transaction.Transaction

  @type t :: %__MODULE__{
    header: header(),
    transactions: [Transaction.t()],
    hash: binary() | nil
  }

  @type header :: %{
    index: non_neg_integer(),
    previous_hash: binary(),
    timestamp: integer(),
    merkle_root: binary(),
    nonce: non_neg_integer(),
    difficulty: non_neg_integer(),
    consensus_data: map()
  }

  @derive Jason.Encoder
  defstruct [
    :header,
    :transactions,
    :hash
  ]

  @doc """
  Gets the height (index) of the block.
  """
  @spec height(t()) :: non_neg_integer()
  def height(%__MODULE__{header: %{index: index}}), do: index

  @doc """
  Checks if block has valid structure (public version of private function).
  """
  @spec valid_structure?(t()) :: boolean()
  def valid_structure?(%__MODULE__{} = block) do
    valid?(block)
  end

  @doc """
  Serializes block to binary format.
  """
  @spec to_binary(t()) :: binary()
  def to_binary(%__MODULE__{} = block) do
    :erlang.term_to_binary(block)
  end

  @doc """
  Deserializes block from binary format.
  """
  @spec from_binary(binary()) :: t()
  def from_binary(binary) when is_binary(binary) do
    :erlang.binary_to_term(binary)
  end

  @doc """
  Creates a new block with the given parameters.
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    header = %{
      index: Keyword.fetch!(opts, :index),
      previous_hash: Keyword.fetch!(opts, :previous_hash),
      timestamp: Keyword.get(opts, :timestamp, System.system_time(:second)),
      merkle_root: Keyword.get(opts, :merkle_root, <<0::256>>),
      nonce: Keyword.get(opts, :nonce, 0),
      difficulty: Keyword.get(opts, :difficulty, 1),
      consensus_data: Keyword.get(opts, :consensus_data, %{})
    }

    transactions = Keyword.get(opts, :transactions, [])

    %__MODULE__{
      header: header,
      transactions: transactions
    }
    |> calculate_merkle_root()
    |> calculate_hash()
  end

  @doc """
  Creates the hardcoded Bastille genesis block.

  Genesis block parameters:
  - Index: 0 (genesis)
  - Timestamp: July 14, 2025 00:00:00 UTC (Bastille Day)
  - Previous hash: All zeros (no previous block)
  - Difficulty: 0 (no mining required for genesis)
  - Fixed genesis transaction to "1789Revolution" address
  - Hardcoded hash (not mined)
  """
  @spec genesis() :: t()
  def genesis do
    # July 14, 2025 00:00:00 UTC (Bastille Day) - Unix timestamp
    bastille_day_2025 = 1_752_422_400

    # Create the genesis transaction
    genesis_transaction = Transaction.new([
      from: "1789Genesis",
      to: "1789Revolution",
      amount: 178_900_000_000_000_000, # 1789 BAST initial supply (1 block reward worth)
      fee: 0,
      nonce: 0,
      timestamp: bastille_day_2025,
      data: "Liberté, Égalité, Fraternité",
      signature_type: :coinbase,
      signature: %{type: :coinbase}
    ])

    # Calculate merkle root for genesis transaction
    genesis_merkle_root = Transaction.calculate_hash(genesis_transaction)

    # Create genesis block with hardcoded values
    genesis_block = %__MODULE__{
      header: %{
        index: 0,
        previous_hash: <<0::256>>,
        timestamp: bastille_day_2025,
        merkle_root: genesis_merkle_root,
        nonce: 1789, # Symbolic nonce for French Revolution year
        difficulty: 0, # No difficulty for genesis
        consensus_data: %{
          genesis: true,
          network: "bastille",
          version: "1.0.0"
        }
      },
      transactions: [genesis_transaction],
      hash: nil # Will be calculated as hardcoded hash
    }

    # Calculate and set the hardcoded genesis hash
    %{genesis_block | hash: calculate_genesis_hash(genesis_block)}
  end

  # Private function to calculate the hardcoded genesis hash
  defp calculate_genesis_hash(block) do
    # Calculate a deterministic genesis hash
    # This ensures the genesis hash is always the same
    block_data = serialize_for_hash(block)

    # Simple hash calculation for genesis
    :crypto.hash(:sha256, block_data)
  end

  @doc """
  Calculates the hash of a block using SHA256 (for block templates).
  """
  @spec calculate_hash(t()) :: t()
  def calculate_hash(%__MODULE__{header: header} = block) do
    hash_data = [
      <<header.index::64>>,
      header.previous_hash,
      <<header.timestamp::64>>,
      header.merkle_root,
      <<header.nonce::64>>,
      <<header.difficulty::32>>,
      :erlang.term_to_binary(header.consensus_data)
    ]

    hash = CryptoUtils.sha256(hash_data)
    %{block | hash: hash}
  end

  @doc """
  Calculates the hash of a block using Blake3 (for mined blocks).
  Uses double Blake3 hashing for optimal performance/security balance.
  """
  @spec calculate_blake3_hash(t()) :: t()
  def calculate_blake3_hash(%__MODULE__{} = block) do
    # Use centralized hash calculation for consistency
    hash = Mining.calculate_block_hash(block)
    %{block | hash: hash}
  end

  @doc """
  Calculates the Merkle root of transactions in the block.
  """
  @spec calculate_merkle_root(t()) :: t()
  def calculate_merkle_root(%__MODULE__{transactions: []} = block) do
    put_in(block.header.merkle_root, <<0::256>>)
  end

  def calculate_merkle_root(%__MODULE__{transactions: txs} = block) do
    merkle_root =
      txs
      |> Enum.map(&Transaction.hash/1)
      |> build_merkle_tree()

    put_in(block.header.merkle_root, merkle_root)
  end

  # Calculates the Merkle root from a list of transactions directly.
  @spec calculate_merkle_root(list(Transaction.t())) :: binary()
  def calculate_merkle_root(transactions) when is_list(transactions) do
    case transactions do
      [] -> <<0::256>>
      txs ->
        txs
        |> Enum.map(&Transaction.hash/1)
        |> build_merkle_tree()
    end
  end

  @doc """
  Validates a block structure and transactions.
  """
  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{} = block) do
    with true <- valid_header?(block.header),
         true <- valid_transactions?(block.transactions),
         true <- valid_merkle_root?(block),
         true <- valid_hash?(block) do
      true
    else
      _ -> false
    end
  end

  @doc """
  Validates block structure WITHOUT hash validation (for tests only).
  """
  @spec valid_structure_without_hash?(t()) :: boolean()
  def valid_structure_without_hash?(%__MODULE__{} = block) do
    with true <- valid_header?(block.header),
         true <- valid_transactions?(block.transactions),
         true <- valid_merkle_root?(block) do
      true
    else
      _ -> false
    end
  end

  @doc """
  Serializes a block to binary format for hashing.
  """
  @spec serialize(%__MODULE__{}) :: binary()
  def serialize(%__MODULE__{header: header} = _block) do
    # Create deterministic binary representation
    <<
      header.index::64,
      header.previous_hash::binary,
      header.timestamp::64,
      header.merkle_root::binary,
      header.difficulty::32,
      header.nonce::64
    >>
  end

  @doc """
  Serializes a block for mining - Bitcoin-like serialization.
  """
  @spec serialize_for_mining(%__MODULE__{}) :: binary()
  def serialize_for_mining(%__MODULE__{} = block) do
    # Use centralized serialization for consistency
    Mining.serialize_block_for_mining(block)
  end

  # Private helper for genesis hash calculation
  defp serialize_for_hash(%__MODULE__{header: header, transactions: transactions}) do
    # Create deterministic serialization for genesis hash
    transaction_data = :erlang.term_to_binary(transactions)

    # Ensure all header fields are binaries
    previous_hash = case header.previous_hash do
      bin when is_binary(bin) -> bin
      nil -> <<0::256>>
      _ -> <<0::256>>
    end

    merkle_root = case header.merkle_root do
      bin when is_binary(bin) -> bin
      nil -> <<0::256>>
      _ -> <<0::256>>
    end

    # Create header data
    header_data = <<
      header.index::64,
      header.timestamp::64,
      header.difficulty::32,
      header.nonce::64
    >>

    # Combine all parts safely
    header_data <> previous_hash <> merkle_root <> transaction_data
  end

  # Private functions

  defp valid_header?(%{index: i, timestamp: t, difficulty: d})
    when is_integer(i) and i >= 0 and is_integer(t) and is_integer(d) and d > 0 do
    true
  end
  defp valid_header?(_), do: false

  defp valid_transactions?(transactions) do
    Enum.all?(transactions, &Transaction.valid?/1)
  end

  defp valid_merkle_root?(%__MODULE__{} = block) do
    expected = calculate_merkle_root(block)
    expected.header.merkle_root == block.header.merkle_root
  end

  def valid_hash?(%__MODULE__{} = block) do
    # ABSOLUTE SECURITY: Every block MUST have a valid Blake3 hash
    # No exceptions, even for tests
    if is_nil(block.hash) do
      false  # ← Immediate rejection of blocks without hash
    else
      # ALWAYS Triple Blake3 - no bypass possible
      expected_blake3 = calculate_blake3_hash(%{block | hash: nil})
      expected_blake3.hash == block.hash
    end
  end

  defp build_merkle_tree([hash]), do: hash
  defp build_merkle_tree(hashes) do
    hashes
    |> Enum.chunk_every(2)
    |> Enum.map(fn
      [left, right] -> CryptoUtils.sha256([left, right])
      [single] -> single
    end)
    |> build_merkle_tree()
  end
end
