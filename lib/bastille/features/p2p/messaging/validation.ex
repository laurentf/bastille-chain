defmodule Bastille.Features.P2P.Messaging.Validation do
  @moduledoc """
  Minimal validation helpers for P2P protocol.

  Since protobuf enforces strict type and structure validation,
  this module only handles network-specific validation that
  protobuf cannot check (network compatibility, magic values).
  """

  @type network :: :mainnet | :testnet

  @doc """
  Validate that a peer's network identifiers match our local network.
  Returns :ok or {:error, :network_mismatch}.
  """
  @spec validate_network(map(), network(), String.t()) :: :ok | {:error, :network_mismatch}
  def validate_network(%{"network" => peer_network, "magic" => peer_magic}, local_network, local_magic)
      when is_atom(local_network) and is_binary(local_magic) do
    valid_network? = peer_network in ["mainnet", "testnet"]
    valid_magic? = is_binary(peer_magic) and byte_size(peer_magic) in 8..64

    cond do
      not valid_network? -> {:error, :network_mismatch}
      not valid_magic? -> {:error, :network_mismatch}
      peer_network != to_string(local_network) -> {:error, :network_mismatch}
      peer_magic != local_magic -> {:error, :network_mismatch}
      true -> :ok
    end
  end

  def validate_network(_payload, _local_network, _local_magic), do: {:error, :network_mismatch}

  @doc """
  Basic validation of version payload - only checks critical network fields.
  Protobuf already enforces type and structure validation.
  """
  @spec validate_version_payload(map()) :: :ok | {:error, term()}
  def validate_version_payload(%{} = payload) do
    # Only validate fields critical for network compatibility
    case expect_string(payload, ["network", "magic", "user_agent"]) do
      :ok -> :ok
      {:error, _} = err -> err
    end
  end

  def validate_version_payload(_), do: {:error, :invalid_version_payload}

  @doc """
  Simplified message validation - protobuf handles type/structure validation.
  Only validates business logic that protobuf cannot enforce.
  """
  @spec validate_message(atom(), any()) :: :ok | {:error, term()}
  def validate_message(:version, %{} = payload), do: validate_version_payload(payload)
  def validate_message(:block, %{} = payload), do: validate_block_transaction_count(payload)
  # All other messages: protobuf enforces structure, just allow
  def validate_message(_, _), do: :ok

  # Only business logic validation that protobuf cannot enforce
  @max_transactions_per_block 100_000

  @spec validate_block_transaction_count(map()) :: :ok | {:error, term()}
  defp validate_block_transaction_count(%{"transactions" => txs}) when is_list(txs) do
    if length(txs) <= @max_transactions_per_block do
      :ok
    else
      {:error, :too_many_transactions}
    end
  end
  defp validate_block_transaction_count(_), do: :ok

  @doc """
  Constant-time comparison for binaries/iodata.
  Returns true only if both inputs are byte-equal and same length.
  """
  @spec secure_equal(iodata(), iodata()) :: boolean()
  def secure_equal(a, b) do
    bin_a = :erlang.iolist_to_binary(a)
    bin_b = :erlang.iolist_to_binary(b)

    if byte_size(bin_a) != byte_size(bin_b) do
      false
    else
      bytes_a = :binary.bin_to_list(bin_a)
      bytes_b = :binary.bin_to_list(bin_b)
      diff = Enum.reduce(Enum.zip(bytes_a, bytes_b), 0, fn {x, y}, acc -> Bitwise.bor(acc, Bitwise.bxor(x, y)) end)
      diff == 0
    end
  end

  # Minimal helper for string field validation
  defp expect_string(payload, keys) do
    Enum.reduce_while(keys, :ok, fn k, _ ->
      case Map.fetch(payload, k) do
        {:ok, v} when is_binary(v) and byte_size(v) > 0 -> {:cont, :ok}
        _ -> {:halt, {:error, {:invalid_field, k}}}
      end
    end)
  end
end
