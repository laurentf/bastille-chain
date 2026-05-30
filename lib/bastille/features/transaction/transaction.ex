defmodule Bastille.Features.Transaction.Transaction do
  @moduledoc """
  Core Transaction data structure and operations.

  Now supports:
  - "1789..." Bastille address format
  - Post-quantum multi-signature with 2/3 threshold
  - Legacy secp256k1 compatibility
  - 14-decimal precision with "juillet" smallest unit
  """

  require Logger

  alias Bastille.Shared.{Address, Crypto, CryptoUtils}
  alias Bastille.Features.Tokenomics.Token
  alias Bastille.Infrastructure.Storage.CubDB.State

  @type t :: %__MODULE__{
          # "1789..." format address
          from: String.t(),
          # "1789..." format address
          to: String.t(),
          # Amount in juillet (14 decimals)
          amount: Token.amount_juillet(),
          # Fee in juillet
          fee: Token.amount_juillet(),
          # Transaction nonce
          nonce: non_neg_integer(),
          # Unix timestamp
          timestamp: integer(),
          # Additional data payload
          data: binary(),
          # Post-quantum or legacy signature
          signature: map() | nil,
          # :post_quantum_2_of_3 | :secp256k1
          signature_type: atom(),
          # Sender's 3 PQ public keys, carried so any node can verify the
          # signature without prior knowledge of the sender. Bound to `from`
          # (see verify_signature/1); excluded from the hash and signed message.
          public_keys: %{dilithium: binary(), falcon: binary(), sphincs: binary()} | nil,
          # Transaction hash
          hash: binary() | nil
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
    :public_keys,
    :hash
  ]

  @doc """
  Creates a new transaction with post-quantum addresses.

  `from` and `to` are canonicalized to lowercase before being stored on the
  struct so the tx hash and the State storage key are stable regardless of
  whether the caller supplied the checksummed display form or the
  canonical form. Callers should still validate the input form via
  `Bastille.Shared.Address.valid?/1` BEFORE calling `new/1` — this is the
  caller's responsibility (typically the RPC handler).
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    base_tx = %__MODULE__{
      from: opts |> Keyword.fetch!(:from) |> Address.canonical(),
      to: opts |> Keyword.fetch!(:to) |> Address.canonical(),
      amount: Keyword.fetch!(opts, :amount),
      # placeholder, will set below
      fee: 0,
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
    # 0.0001 BAST per byte (in juillet)
    fee_per_byte = 10_000
    # 0.001 BAST minimum (in juillet)
    min_fee = 100_000
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
      # Special genesis address for coinbase
      from: "1789Genesis",
      to: miner_address,
      amount: reward_juillet,
      fee: 0,
      nonce: 0,
      timestamp: System.system_time(:second),
      data:
        "Coinbase transaction for block #{block_height} - Reward: #{Token.format_bast(reward_juillet)}",
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
    total_fees =
      transactions
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

    fee_info =
      if total_fees > 0 do
        " | Fees: #{Token.format_bast(total_fees)} (70% to miner: #{Token.format_bast(miner_fee_share)}, 30% burned: #{Token.format_bast(burned_amount)})"
      else
        ""
      end

    %__MODULE__{
      # Special genesis address for coinbase
      from: "1789Genesis",
      to: miner_address,
      amount: total_reward,
      fee: 0,
      nonce: 0,
      timestamp: System.system_time(:second),
      data:
        "Coinbase transaction for block #{block_height} - Base reward: #{Token.format_bast(base_reward)}#{fee_info}",
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

    Logger.debug("🔍 Verifying tx signature #{encode_hash(tx.hash)}")
    Logger.debug("   └─ chain_id: #{chain_id_bytes()}")
    Logger.debug("   └─ fee: #{tx.fee} juillet, data_size: #{byte_size(tx.data || <<>>)} bytes")

    case resolve_public_keys(tx) do
      {:ok, public_keys} ->
        case Crypto.verify(message, tx.signature, public_keys) do
          true ->
            true

          false ->
            Logger.warning("⚠️ Tx signature invalid for #{encode_hash(tx.hash)} (from #{tx.from})")
            false
        end

      {:error, :embedded_key_mismatch} ->
        Logger.warning(
          "⚠️ Tx rejected: embedded public keys do not hash to sender #{tx.from} (#{encode_hash(tx.hash)})"
        )

        false

      {:error, :not_found} ->
        Logger.warning("⚠️ Tx signature unverifiable: no public keys stored for #{tx.from}")
        false

      {:error, reason} ->
        Logger.warning(
          "⚠️ Tx signature unverifiable: pubkey lookup failed (#{inspect(reason)}) for #{tx.from}"
        )

        false
    end
  end

  # REMOVED: Legacy secp256k1 signature support for security reasons
  # All transactions must use post-quantum signatures

  def verify_signature(_), do: false

  # Embedded keys are trusted only once proven to hash to `from`; without that
  # check an attacker could attach their own keys + signature and impersonate any
  # address. Falls back to locally-stored keys when the tx carries none.
  defp resolve_public_keys(%__MODULE__{
         public_keys: %{dilithium: d, falcon: f, sphincs: s} = public_keys,
         from: from
       })
       when is_binary(d) and is_binary(f) and is_binary(s) do
    if Crypto.address_from_public_keys(public_keys) == Address.canonical(from) do
      {:ok, public_keys}
    else
      {:error, :embedded_key_mismatch}
    end
  end

  defp resolve_public_keys(%__MODULE__{from: from}), do: State.get_public_keys(from)

  defp encode_hash(hash) when is_binary(hash),
    do: hash |> Base.encode16(case: :lower) |> String.slice(0, 16)

  defp encode_hash(_), do: "<no-hash>"

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
  Convert a transaction to a JSON-safe plain map.

  This is the canonical wire format for the RPC layer — JSON over HTTP.
  Binary fields (hash, signature components) are hex-encoded. Atoms are
  converted to strings. Use this instead of `to_binary/1` whenever a
  transaction crosses the RPC boundary so consumers never need to call
  `:erlang.binary_to_term/1` on untrusted bytes.
  """
  @spec to_json_map(t()) :: map()
  def to_json_map(%__MODULE__{} = tx) do
    base = %{
      "from" => tx.from,
      "to" => tx.to,
      "amount" => tx.amount,
      "fee" => tx.fee,
      "nonce" => tx.nonce,
      "timestamp" => tx.timestamp,
      "data" => tx.data || "",
      "signature_type" => Atom.to_string(tx.signature_type),
      "hash" => encode_binary(tx.hash)
    }

    base = maybe_put_public_keys(base, tx.public_keys)

    case tx.signature do
      nil ->
        base

      %{dilithium: d, falcon: f, sphincs: s} ->
        Map.put(base, "signature", %{
          "dilithium" => encode_binary(d),
          "falcon" => encode_binary(f),
          "sphincs" => encode_binary(s)
        })

      %{type: :coinbase} ->
        # Coinbase txs never cross the RPC boundary, but expose a tag so
        # accidental serialization doesn't leak struct internals.
        Map.put(base, "signature", %{"type" => "coinbase"})
    end
  end

  @doc """
  Parse a transaction from a JSON-derived plain map.

  Strict, fail-closed validation. Returns `{:ok, %Transaction{}}` on
  success or `{:error, reason}` otherwise. This is the entry point for
  every RPC handler that receives an unsigned or signed transaction —
  NEVER call `:erlang.binary_to_term/1` on RPC input. ETF can inject
  arbitrary atoms (exhausting the atom table) and other host terms.

  Only `signature_type: "post_quantum_2_of_3"` is accepted from the wire.
  Coinbase transactions are constructed internally and never flow through
  this function.
  """
  @spec from_json_map(map()) :: {:ok, t()} | {:error, term()}
  def from_json_map(%{} = m) do
    with {:ok, from} <- fetch_address(m, "from"),
         {:ok, to} <- fetch_address(m, "to"),
         {:ok, amount} <- fetch_non_neg_int(m, "amount"),
         {:ok, fee} <- fetch_non_neg_int(m, "fee"),
         {:ok, nonce} <- fetch_non_neg_int(m, "nonce"),
         {:ok, timestamp} <- fetch_int(m, "timestamp"),
         {:ok, data} <- fetch_optional_string(m, "data"),
         {:ok, sig_type} <- fetch_signature_type(m),
         {:ok, hash} <- fetch_hex_bytes(m, "hash", 32),
         {:ok, signature} <- fetch_signature(m, sig_type),
         {:ok, public_keys} <- fetch_public_keys(m) do
      {:ok,
       %__MODULE__{
         from: from,
         to: to,
         amount: amount,
         fee: fee,
         nonce: nonce,
         timestamp: timestamp,
         data: data,
         signature_type: sig_type,
         hash: hash,
         signature: signature,
         public_keys: public_keys
       }}
    end
  end

  def from_json_map(_), do: {:error, :invalid_payload}

  @doc """
  Serializes transaction to binary format.

  ⚠️ Internal storage only. Use `to_json_map/1` for the RPC wire and
  never accept `:erlang.term_to_binary/1` output from untrusted sources.
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

  Deterministic message bound to the configured network so that:
  - any modification of `fee` or `data` invalidates the signature (otherwise
    a MITM could rewrite either field while keeping the signature valid)
  - a signature minted on testnet cannot be replayed on mainnet

  Layout (fixed offsets so verification side reconstructs it identically):
      chain_id_size::32
      chain_id::binary
      from::binary       (44 bytes — fixed-length prefix + 40 hex)
      to::binary         (44 bytes)
      amount::64
      fee::64
      nonce::64
      timestamp::64
      data_size::32
      data::binary
  """
  def serialize_for_signing(%__MODULE__{} = tx) do
    chain_id = chain_id_bytes()
    data = tx.data || <<>>

    <<
      byte_size(chain_id)::32,
      chain_id::binary,
      tx.from::binary,
      tx.to::binary,
      tx.amount::64,
      tx.fee::64,
      tx.nonce::64,
      tx.timestamp::64,
      byte_size(data)::32,
      data::binary
    >>
  end

  # Network identifier embedded in the signed message. Reads from the same
  # config the P2P layer uses (`Bastille.Features.P2P.Messaging.Messages.get_network_magic/1`).
  # Atom is converted to a binary so it travels deterministically.
  defp chain_id_bytes do
    :bastille
    |> Application.get_env(:network, :testnet)
    |> Atom.to_string()
  end

  # Private functions

  defp valid_structure?(%__MODULE__{
         amount: amount,
         fee: fee,
         nonce: nonce,
         timestamp: timestamp
       })
       when is_integer(nonce) and nonce >= 0 and
              is_integer(timestamp) do
    Token.valid_amount?(amount) and Token.valid_amount?(fee)
  end

  defp valid_structure?(_), do: false

  defp valid_addresses?(%__MODULE__{from: from, to: to}) do
    valid_address?(from) and valid_address?(to)
  end

  defp valid_address?(address) when is_binary(address) do
    cond do
      # Synthetic coinbase sender label
      address == "1789Genesis" -> true
      # Legacy format
      String.starts_with?(address, "legacy_") -> true
      # Standard format + EIP-55-like checksum
      true -> Address.valid?(address)
    end
  end

  defp valid_address?(_), do: false

  defp valid_signature?(%__MODULE__{signature: nil}), do: false
  # Coinbase
  defp valid_signature?(%__MODULE__{signature: %{type: :coinbase}}), do: true
  defp valid_signature?(tx), do: verify_signature(tx)

  defp valid_hash?(%__MODULE__{} = tx) do
    expected = calculate_hash(%{tx | hash: nil})
    expected.hash == tx.hash
  end

  defp atom_to_binary(atom) when is_atom(atom) do
    atom |> Atom.to_string() |> :binary.copy()
  end

  defp atom_to_binary(other), do: to_string(other)

  # === JSON-map helpers (safe RPC parsing) ===

  defp encode_binary(nil), do: ""
  defp encode_binary(b) when is_binary(b), do: Base.encode16(b, case: :lower)

  defp maybe_put_public_keys(base, %{dilithium: d, falcon: f, sphincs: s})
       when is_binary(d) and is_binary(f) and is_binary(s) do
    Map.put(base, "public_keys", %{
      "dilithium" => encode_binary(d),
      "falcon" => encode_binary(f),
      "sphincs" => encode_binary(s)
    })
  end

  defp maybe_put_public_keys(base, _), do: base

  # Optional on the wire: unsigned transactions carry none, signed ones embed
  # the sender's three public keys so receiving nodes can verify them.
  defp fetch_public_keys(m) do
    case Map.get(m, "public_keys") do
      nil ->
        {:ok, nil}

      %{"dilithium" => d, "falcon" => f, "sphincs" => s}
      when is_binary(d) and is_binary(f) and is_binary(s) ->
        with {:ok, dilithium} <- decode_hex(d),
             {:ok, falcon} <- decode_hex(f),
             {:ok, sphincs} <- decode_hex(s) do
          {:ok, %{dilithium: dilithium, falcon: falcon, sphincs: sphincs}}
        end

      _ ->
        {:error, :invalid_public_keys_shape}
    end
  end

  defp fetch_address(m, key) do
    case Map.get(m, key) do
      v when is_binary(v) and v != "" ->
        if Address.valid?(v) do
          {:ok, Address.canonical(v)}
        else
          {:error, {:invalid_address, key}}
        end

      _ ->
        {:error, {:missing_field, key}}
    end
  end

  defp fetch_int(m, key) do
    case Map.get(m, key) do
      v when is_integer(v) -> {:ok, v}
      _ -> {:error, {:missing_or_non_integer, key}}
    end
  end

  defp fetch_non_neg_int(m, key) do
    case fetch_int(m, key) do
      {:ok, v} when v >= 0 -> {:ok, v}
      {:ok, _} -> {:error, {:negative_value, key}}
      err -> err
    end
  end

  defp fetch_optional_string(m, key) do
    case Map.get(m, key, "") do
      v when is_binary(v) -> {:ok, v}
      _ -> {:error, {:invalid_string, key}}
    end
  end

  defp fetch_signature_type(m) do
    case Map.get(m, "signature_type") do
      "post_quantum_2_of_3" -> {:ok, :post_quantum_2_of_3}
      other -> {:error, {:unsupported_signature_type, other}}
    end
  end

  defp fetch_hex_bytes(m, key, expected_size) do
    with v when is_binary(v) <- Map.get(m, key),
         {:ok, bytes} <- Base.decode16(v, case: :mixed),
         true <- byte_size(bytes) == expected_size do
      {:ok, bytes}
    else
      nil -> {:error, {:missing_field, key}}
      false -> {:error, {:wrong_byte_size, key, expected_size}}
      :error -> {:error, {:invalid_hex, key}}
      _ -> {:error, {:invalid_field, key}}
    end
  end

  # Signature is optional on unsigned transactions; required on signed ones.
  # The caller (RPC layer) decides whether `nil` is acceptable for its flow.
  defp fetch_signature(m, :post_quantum_2_of_3) do
    case Map.get(m, "signature") do
      nil ->
        {:ok, nil}

      %{"dilithium" => d, "falcon" => f, "sphincs" => s}
      when is_binary(d) and is_binary(f) and is_binary(s) ->
        with {:ok, dilithium} <- decode_hex(d),
             {:ok, falcon} <- decode_hex(f),
             {:ok, sphincs} <- decode_hex(s) do
          {:ok, %{dilithium: dilithium, falcon: falcon, sphincs: sphincs}}
        end

      _ ->
        {:error, :invalid_signature_shape}
    end
  end

  defp decode_hex(v) when is_binary(v) do
    case Base.decode16(v, case: :mixed) do
      {:ok, bytes} -> {:ok, bytes}
      :error -> {:error, :invalid_hex}
    end
  end
end
