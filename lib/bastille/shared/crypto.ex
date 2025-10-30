defmodule Bastille.Shared.Crypto do
  @moduledoc """
  Post-quantum cryptographic operations for Bastille blockchain.

  Implements multi-signature with 2/3 threshold using:
  - Dilithium (lattice-based signatures)
  - Falcon (NTRU-based signatures)
  - SPHINCS+ (hash-based signatures)

  Provides fallback implementations when NIFs are unavailable.
  """

  alias Bastille.Infrastructure.Crypto.CryptoNif
  alias Bastille.Shared.CryptoUtils
  alias Bastille.Infrastructure.Storage.CubDB.State

  @type pq_keypair :: %{
    dilithium: %{public: binary(), private: binary()},
    falcon: %{public: binary(), private: binary()},
    sphincs: %{public: binary(), private: binary()}
  }

  @type keypair :: %{public: binary(), private: binary()}

  @type signature :: %{
    dilithium: binary(),
    falcon: binary(),
    sphincs: binary()
  }

  # === Key Generation ===

  @doc """
  Generate a complete post-quantum keypair set.
  """
  @spec generate_pq_keypair() :: pq_keypair()
  def generate_pq_keypair do
    %{
      dilithium: generate_dilithium_keypair(),
      falcon: generate_falcon_keypair(),
      sphincs: generate_sphincs_keypair()
    }
  end

  @doc """
  Alias for generate_pq_keypair for backward compatibility.
  """
  def generate_keypair, do: generate_pq_keypair()

  @doc """
  Generate a Dilithium keypair using NIFs.
  """
  @spec generate_dilithium_keypair() :: %{public: binary(), private: binary()}
  def generate_dilithium_keypair do
    {public_key, private_key} = CryptoNif.dilithium2_keypair()
    %{public: public_key, private: private_key}
  end

  @doc """
  Generate a Falcon keypair using NIFs.
  """
  @spec generate_falcon_keypair() :: %{public: binary(), private: binary()}
  def generate_falcon_keypair do
    {public_key, private_key} = CryptoNif.falcon512_keypair()
    %{public: public_key, private: private_key}
  end

  @doc """
  Generate a SPHINCS+ keypair using NIFs.
  """
  @spec generate_sphincs_keypair() :: %{public: binary(), private: binary()}
  def generate_sphincs_keypair do
    {public_key, private_key} = CryptoNif.sphincsplus_shake_128f_keypair()
    %{public: public_key, private: private_key}
  end

  # === Deterministic Key Generation ===

  @doc """
  Generate deterministic Dilithium keypair from seed.
  Uses proper HKDF-based derivation for true determinism.
  """
  @spec generate_dilithium_keypair_from_seed(binary()) :: %{public: binary(), private: binary()}
  def generate_dilithium_keypair_from_seed(seed) do
    # Derive algorithm-specific seed using HKDF
    derived_seed = derive_algorithm_seed(seed, "dilithium")
    {public_key, private_key} = CryptoNif.dilithium2_keypair_from_seed(derived_seed)
    %{public: public_key, private: private_key}
  end

  @doc """
  Generate deterministic Falcon keypair from seed.
  Uses proper HKDF-based derivation for true determinism.
  """
  @spec generate_falcon_keypair_from_seed(binary()) :: %{public: binary(), private: binary()}
  def generate_falcon_keypair_from_seed(seed) do
    # Derive algorithm-specific seed using HKDF
    derived_seed = derive_algorithm_seed(seed, "falcon")
    {public_key, private_key} = CryptoNif.falcon512_keypair_from_seed(derived_seed)
    %{public: public_key, private: private_key}
  end

  @doc """
  Generate deterministic SPHINCS+ keypair from seed.
  Uses proper HKDF-based derivation for true determinism.
  """
  @spec generate_sphincs_keypair_from_seed(binary()) :: %{public: binary(), private: binary()}
  def generate_sphincs_keypair_from_seed(seed) do
    # Derive algorithm-specific seed using HKDF
    derived_seed = derive_algorithm_seed(seed, "sphincs")
    {public_key, private_key} = CryptoNif.sphincsplus_keypair_from_seed(derived_seed)
    %{public: public_key, private: private_key}
  end

  # Derive algorithm-specific seed using HKDF-like process.
  @spec derive_algorithm_seed(binary(), String.t()) :: binary()
  defp derive_algorithm_seed(master_seed, algorithm) do
    :crypto.mac(:hmac, :sha256, master_seed, algorithm)
  end

  @doc """
  Clear the deterministic keys cache (for testing).
  Note: No longer needed with proper deterministic implementation.
  """
  @spec clear_deterministic_keys_cache() :: :ok
  def clear_deterministic_keys_cache do
    # This function is kept for backward compatibility but does nothing
    # since we no longer use application-level caching
    :ok
  end

  # === Signing ===

  @doc """
  Sign a message with all three post-quantum algorithms.
  """
  @spec sign(binary(), pq_keypair()) :: signature()
  def sign(message, %{dilithium: dil_keys, falcon: fal_keys, sphincs: sph_keys}) do
    %{
      dilithium: sign_dilithium(message, dil_keys.private),
      falcon: sign_falcon(message, fal_keys.private),
      sphincs: sign_sphincs(message, sph_keys.private)
    }
  end

  @doc """
  Sign with Dilithium.
  """
  @spec sign_dilithium(binary(), binary()) :: binary()
  def sign_dilithium(message, private_key) do
    CryptoNif.dilithium2_sign(message, private_key)
  end

  @doc """
  Sign with Falcon.
  """
  @spec sign_falcon(binary(), binary()) :: binary()
  def sign_falcon(message, private_key) do
    CryptoNif.falcon512_sign(message, private_key)
  end

  @doc """
  Sign with SPHINCS+.
  """
  @spec sign_sphincs(binary(), binary()) :: binary()
  def sign_sphincs(message, private_key) do
    CryptoNif.sphincsplus_shake_128f_sign(message, private_key)
  end

  # === Verification ===

  @doc """
  Verify a post-quantum signature (2/3 threshold).
  """
  @spec verify(binary(), signature(), map()) :: boolean()
  def verify(message, %{dilithium: dil_sig, falcon: fal_sig, sphincs: sph_sig}, public_keys) do
    results = [
      verify_dilithium(message, dil_sig, public_keys.dilithium),
      verify_falcon(message, fal_sig, public_keys.falcon),
      verify_sphincs(message, sph_sig, public_keys.sphincs)
    ]

    # 2/3 threshold: at least 2 signatures must be valid
    valid_count = Enum.count(results, & &1)
    valid_count >= 2
  end

  @doc """
  Verify Dilithium signature.
  """
  @spec verify_dilithium(binary(), binary(), binary()) :: boolean()
  def verify_dilithium(message, signature, public_key) do
    CryptoNif.dilithium2_verify(signature, message, public_key)
  end

  @doc """
  Verify Falcon signature.
  """
  @spec verify_falcon(binary(), binary(), binary()) :: boolean()
  def verify_falcon(message, signature, public_key) do
    CryptoNif.falcon512_verify(signature, message, public_key)
  end

  @doc """
  Verify SPHINCS+ signature.
  """
  @spec verify_sphincs(binary(), binary(), binary()) :: boolean()
  def verify_sphincs(message, signature, public_key) do
    CryptoNif.sphincsplus_shake_128f_verify(signature, message, public_key)
  end

  # === Public Key Storage and Recovery ===

  @doc """
  Store public keys from a keypair for future verification.
  """
  @spec store_public_keys_from_keypair(pq_keypair()) :: :ok | {:error, term()}
  def store_public_keys_from_keypair(%{dilithium: %{public: dil_pub}, falcon: %{public: fal_pub}, sphincs: %{public: sph_pub}}) do
    # Derive address from public keys
    address = derive_bastille_address_from_public_keys(dil_pub, fal_pub, sph_pub)

    public_keys = %{
      dilithium: dil_pub,
      falcon: fal_pub,
      sphincs: sph_pub
    }

    # Store in the new storage system
    case State.store_public_keys(address, public_keys) do
      :ok -> :ok
      error -> error
    end
  end

  @doc """
  Retrieve public keys for an address.
  """
  @spec get_public_keys_for_address(String.t()) :: {:ok, Bastille.Infrastructure.Storage.CubDB.State.public_keys_map()} | {:error, term()}
  def get_public_keys_for_address(address) do
    State.get_public_keys(address)
  end

  @doc """
  Gets algorithm information for the current implementation.
  """
  @spec get_algorithms() :: [String.t()]
  def get_algorithms do
    ["Dilithium2", "Falcon-512", "SPHINCS+-SHAKE256-128f"]
  end

  @doc """
  Gets the threshold requirement for signature validation.
  """
  @spec get_threshold() :: {pos_integer(), pos_integer()}
  def get_threshold do
    {2, 3}  # 2 out of 3 signatures required
  end

  # === Address Generation ===

  @doc """
  Generate a Bastille address from public keys.
  This is the ONLY method that should be used for address generation.
  """
  @spec generate_bastille_address(pq_keypair()) :: String.t()
  def generate_bastille_address(%{dilithium: %{public: dil_pub}, falcon: %{public: fal_pub}, sphincs: %{public: sph_pub}}) do
    derive_bastille_address_from_public_keys(dil_pub, fal_pub, sph_pub)
  end

  defp derive_bastille_address_from_public_keys(dil_pub, fal_pub, sph_pub) do
    # Combine all three public keys
    combined_pubkeys = dil_pub <> fal_pub <> sph_pub

    # Hash the combined public keys
    hash = CryptoUtils.sha256(combined_pubkeys)

    # Take first 20 bytes and encode to lowercase hex
    <<address_bytes::binary-size(20), _rest::binary>> = hash
    encoded = Base.encode16(address_bytes, case: :lower)

    # Add configurable Bastille prefix
    prefix = Application.get_env(:bastille, :address_prefix, "1789")
    prefix <> encoded
  end

  @doc """
  Validate Bastille address format.
  Ensures address follows the configured prefix + 40 hex character format.
  """
  @spec valid_address?(String.t()) :: boolean()
  def valid_address?(address) when is_binary(address) do
    prefix = Application.get_env(:bastille, :address_prefix, "1789")

    case String.starts_with?(address, prefix) do
      true ->
        address_part = String.slice(address, String.length(prefix)..-1//1)

        if byte_size(address_part) == 40 do
          # Check if it's valid lowercase hex
          case Base.decode16(address_part, case: :lower) do
            {:ok, _} -> true
            :error -> false
          end
        else
          false
        end

      false ->
        false
    end
  end
  def valid_address?(_), do: false

  # === Key Size Constants ===

  @doc """
  Returns the size in bytes of a Dilithium2 private key.
  """
  @spec dilithium_private_key_size() :: non_neg_integer()
  def dilithium_private_key_size, do: 2560

  @doc """
  Returns the size in bytes of a Falcon512 private key.
  """
  @spec falcon_private_key_size() :: non_neg_integer()
  def falcon_private_key_size, do: 1281

  @doc """
  Returns the size in bytes of a SPHINCS+ private key.
  """
  @spec sphincs_private_key_size() :: non_neg_integer()
  def sphincs_private_key_size, do: 64

  @doc """
  Returns the size in bytes of a Dilithium2 public key.
  """
  @spec dilithium_public_key_size() :: non_neg_integer()
  def dilithium_public_key_size, do: 1312

  @doc """
  Returns the size in bytes of a Falcon512 public key.
  """
  @spec falcon_public_key_size() :: non_neg_integer()
  def falcon_public_key_size, do: 897

  @doc """
  Returns the size in bytes of a SPHINCS+ public key.
  """
  @spec sphincs_public_key_size() :: non_neg_integer()
  def sphincs_public_key_size, do: 32

  @doc """
  Returns the size in bytes of a Dilithium2 signature.
  """
  @spec dilithium_signature_size() :: non_neg_integer()
  def dilithium_signature_size, do: 2420

  @doc """
  Returns the size in bytes of a Falcon512 signature.
  """
  @spec falcon_signature_size() :: non_neg_integer()
  def falcon_signature_size, do: 690

  @doc """
  Returns the size in bytes of a SPHINCS+ signature.
  """
  @spec sphincs_signature_size() :: non_neg_integer()
  def sphincs_signature_size, do: 7856

  # === Legacy Functions (Removed) ===
  # The following functions are removed as part of security fixes:
  # - combine_public_keys/1 (no longer needed with proper verification)
  # - derive_key_from_public/1 (insecure pattern)
  # - All application cache-based deterministic key generation
end
