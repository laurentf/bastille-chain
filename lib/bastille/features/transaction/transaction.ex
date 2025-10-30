defmodule Bastille.Features.Transaction.Transaction do
  @moduledoc """
  Core Transaction data structure and operations.

  Now supports:
  - "1789..." Bastille address format
  - Post-quantum multi-signature with 2/3 threshold
  - Legacy secp256k1 compatibility
  - 14-decimal precision with "juillet" smallest unit
  """

  alias Bastille.Shared.{Crypto, CryptoUtils}
  alias Bastille.Features.Tokenomics.Token
  alias Bastille.Infrastructure.Storage.CubDB.State

  @type t :: %__MODULE__{
    from: String.t(),                    # "1789..." format address
    to: String.t(),                      # "1789..." format address
    amount: Token.amount_juillet(),      # Amount in juillet (14 decimals)
    fee: Token.amount_juillet(),         # Fee in juillet
    nonce: non_neg_integer(),            # Transaction nonce
    timestamp: integer(),                # Unix timestamp
    data: binary(),                      # Additional data payload
    signature: map() | nil,              # Post-quantum or legacy signature
    signature_type: atom(),              # :post_quantum_2_of_3 | :secp256k1
    hash: binary() | nil                 # Transaction hash
  }

  @derive Jason.Encoder
  defstruct [
    :from,
    :to,
    :amount,
    :fee,
    :nonce,
    :timestamp,
    :data,
    :signature,
    :signature_type,
    :hash
  ]

  @doc """
  Creates a new transaction with post-quantum addresses.
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    base_tx = %__MODULE__{
      from: Keyword.fetch!(opts, :from),
      to: Keyword.fetch!(opts, :to),
      amount: Keyword.fetch!(opts, :amount),
      fee: 0, # placeholder, will set below
      nonce: Keyword.fetch!(opts, :nonce),
      timestamp: Keyword.get(opts, :timestamp, System.system_time(:second)),
      data: Keyword.get(opts, :data, <<>>),
      signature: Keyword.get(opts, :signature),
      signature_type: Keyword.get(opts, :signature_type, :post_quantum_2_of_3),
      hash: nil
    }

    # Always calculate fee on the server, ignore any provided fee value
    fee = calculate_fee(base_tx)
    base_tx = %{base_tx | fee: fee}
    base_tx |> calculate_hash()
  end

  @doc """
  Automatically calculates a transaction fee based on size and fee rate.
  """
  @spec calculate_fee(t()) :: integer()
  def calculate_fee(tx) do
    size = :erlang.term_to_binary(tx) |> byte_size()
    fee_per_byte = 10_000 # 0.0001 BAST per byte (in juillet)
    min_fee = 100_000     # 0.001 BAST minimum (in juillet)
    max(size * fee_per_byte, min_fee)
  end

  @doc """
  Creates a coinbase transaction (block reward) with Bastille address.
  Reward amount is fixed at 1789 BAST per block.
  """
  @spec coinbase(String.t(), non_neg_integer()) :: t()
  def coinbase(miner_address, block_height) do
    reward_juillet = Token.block_reward(block_height)

    %__MODULE__{
      from: "1789Genesis", # Special genesis address for coinbase
      to: miner_address,
      amount: reward_juillet,
      fee: 0,
      nonce: 0,
      timestamp: System.system_time(:second),
      data: "Coinbase transaction for block #{block_height} - Reward: #{Token.format_bast(reward_juillet)}",
      signature: %{type: :coinbase},
      signature_type: :coinbase,
      hash: nil
    }
    |> calculate_hash()
  end

  @doc """
  Creates a coinbase transaction with block reward plus transaction fees.
  Implements 30% fee burn mechanism.
  """
  @spec coinbase_with_fees(String.t(), non_neg_integer(), [t()]) :: t()
  def coinbase_with_fees(miner_address, block_height, transactions) do
    # Fixed block reward (1789 BAST)
    base_reward = Token.block_reward(block_height)

    # Calculate total fees from transactions (excluding coinbase)
    total_fees = transactions
                |> Enum.filter(fn tx -> tx.signature_type != :coinbase end)
                |> Enum.reduce(0, fn tx, acc -> acc + tx.fee end)

    # Apply burn mechanism: miner gets 70% of fees, 30% burned
    miner_fee_share = Token.calculate_remaining_fee(total_fees)
    burned_amount = Token.calculate_burn_amount(total_fees)

    # Track the burn (reduce circulating supply)
    if burned_amount > 0 do
      Token.track_fee_burn(burned_amount)
    end

    # Total miner reward = base reward + 70% of transaction fees
    total_reward = base_reward + miner_fee_share

    fee_info = if total_fees > 0 do
      " | Fees: #{Token.format_bast(total_fees)} (70% to miner: #{Token.format_bast(miner_fee_share)}, 30% burned: #{Token.format_bast(burned_amount)})"
    else
      ""
    end

    %__MODULE__{
      from: "1789Genesis", # Special genesis address for coinbase
      to: miner_address,
      amount: total_reward,
      fee: 0,
      nonce: 0,
      timestamp: System.system_time(:second),
      data: "Coinbase transaction for block #{block_height} - Base reward: #{Token.format_bast(base_reward)}#{fee_info}",
      signature: %{type: :coinbase},
      signature_type: :coinbase,
      hash: nil
    }
    |> calculate_hash()
  end

  @doc """
  Signs a transaction with post-quantum multi-signature.
  """
  @spec sign(%__MODULE__{}, map()) :: %__MODULE__{}
  def sign(%__MODULE__{} = tx, keypair) do
    message = serialize_for_signing(tx)
    signature = Crypto.sign(message, keypair)
    %{tx | signature: signature, signature_type: :post_quantum_2_of_3}
  end



  @doc """
  Calculates the hash of a transaction.
  """
  @spec calculate_hash(t()) :: t()
  def calculate_hash(%__MODULE__{} = tx) do
    hash_data = [
      tx.from,
      tx.to,
      <<tx.amount::64>>,
      <<tx.fee::32>>,
      <<tx.nonce::64>>,
      <<tx.timestamp::64>>,
      tx.data,
      atom_to_binary(tx.signature_type)
    ]

    hash = CryptoUtils.sha256(hash_data)
    %{tx | hash: hash}
  end

  @doc """
  Gets the hash of a transaction.
  """
  @spec hash(t()) :: binary()
  def hash(%__MODULE__{hash: nil} = tx) do
    calculate_hash(tx).hash
  end
  def hash(%__MODULE__{hash: hash}), do: hash

  @doc """
  Validates a transaction with post-quantum or legacy signatures.
  """
  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{} = tx) do
    with true <- valid_structure?(tx),
         true <- valid_addresses?(tx),
         true <- valid_signature?(tx),
         true <- valid_hash?(tx) do
      true
    else
      _ -> false
    end
  end

  @doc """
  TEST ONLY: Validates a transaction without signature verification.
  Used for testing mempool functionality without needing signed transactions.
  """
  @spec valid_for_testing?(t()) :: boolean()
  def valid_for_testing?(%__MODULE__{} = tx) do
    with true <- valid_structure?(tx),
         true <- valid_addresses?(tx),
         true <- valid_hash?(tx) do
      true
    else
      _ -> false
    end
  end

  @doc """
  Verifies the signature of a transaction.
  """
  @spec verify_signature(t()) :: boolean()
  def verify_signature(%__MODULE__{signature_type: :post_quantum_2_of_3} = tx) do
    message = serialize_for_signing(tx)

    # Get public keys for the from address
    case State.get_public_keys(tx.from) do
      {:ok, public_keys} ->
        Crypto.verify(message, tx.signature, public_keys)
      {:error, :not_found} ->
        # If no public keys stored, check if this is a fresh address
        # and try to derive from the transaction signature (not implemented yet)
        false
      {:error, _} ->
        false
    end
  end

  # REMOVED: Legacy secp256k1 signature support for security reasons
  # All transactions must use post-quantum signatures

  def verify_signature(_), do: false

  @doc """
  Converts transaction to display format with human-readable amounts.
  """
  @spec to_display_map(t()) :: map()
  def to_display_map(%__MODULE__{} = tx) do
    %{
      hash: Base.encode16(tx.hash, case: :lower),
      from: tx.from,
      to: tx.to,
      amount: Token.format_bast(tx.amount),
      amount_juillet: tx.amount,
      fee: Token.format_bast(tx.fee),
      fee_juillet: tx.fee,
      nonce: tx.nonce,
      timestamp: tx.timestamp,
      signature_type: tx.signature_type,
      data: Base.encode16(tx.data, case: :lower)
    }
  end

  @doc """
  Checks if this is a Bastille-format transaction.
  """
  @spec bastille_format?(t()) :: boolean()
  def bastille_format?(%__MODULE__{from: from, to: to}) do
    String.starts_with?(from, "1789") and String.starts_with?(to, "1789")
  end

  @doc """
  Serializes transaction to binary format.
  """
  @spec to_binary(t()) :: binary()
  def to_binary(%__MODULE__{} = tx) do
    :erlang.term_to_binary(tx)
  end

  @doc """
  Deserializes transaction from binary format.
  """
  @spec from_binary(binary()) :: {:ok, t()} | {:error, term()}
  def from_binary(binary) when is_binary(binary) do
    try do
      tx = :erlang.binary_to_term(binary)
      if is_struct(tx, __MODULE__) do
        {:ok, tx}
      else
        {:error, :invalid_transaction_format}
      end
    rescue
      _error -> {:error, :invalid_binary_format}
    end
  end

  # Public functions for signing

  @doc """
  Serialize transaction for signing.
  Creates a deterministic message from transaction fields.
  """
  def serialize_for_signing(%__MODULE__{} = tx) do
    # Create deterministic message for signing
    <<
      tx.from::binary,
      tx.to::binary,
      tx.amount::64,
      tx.nonce::64,
      tx.timestamp::64
    >>
  end

  # Private functions

  defp valid_structure?(%__MODULE__{
    amount: amount,
    fee: fee,
    nonce: nonce,
    timestamp: timestamp
  }) when is_integer(nonce) and nonce >= 0 and
           is_integer(timestamp) do
    Token.valid_amount?(amount) and Token.valid_amount?(fee)
  end
  defp valid_structure?(_), do: false

  defp valid_addresses?(%__MODULE__{from: from, to: to}) do
    valid_address?(from) and valid_address?(to)
  end

  defp valid_address?(address) when is_binary(address) do
    prefix = Application.get_env(:bastille, :address_prefix, "1789")

    cond do
      address == prefix <> "Genesis" -> true  # Special genesis address
      String.starts_with?(address, "legacy_") -> true  # Legacy format
      String.starts_with?(address, prefix) -> Crypto.valid_address?(address)
      true -> false
    end
  end
  defp valid_address?(_), do: false

  defp valid_signature?(%__MODULE__{signature: nil}), do: false
  defp valid_signature?(%__MODULE__{signature: %{type: :coinbase}}), do: true  # Coinbase
  defp valid_signature?(tx), do: verify_signature(tx)

  defp valid_hash?(%__MODULE__{} = tx) do
    expected = calculate_hash(%{tx | hash: nil})
    expected.hash == tx.hash
  end

  defp atom_to_binary(atom) when is_atom(atom) do
    atom |> Atom.to_string() |> :binary.copy()
  end
  defp atom_to_binary(other), do: to_string(other)
end
