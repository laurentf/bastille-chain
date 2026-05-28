defmodule Bastille.Shared.Seed do
  @moduledoc """
  🌱 Bastille Seed System - Master seed for key derivation
  Uses a 24-word French mnemonic to derive all cryptographic keys.
  """

  alias Bastille.Shared.Crypto
  alias Bastille.Shared.Mnemonic

  @doc """
  Generates a new 24-word master seed.
  """
  def generate_master_seed do
    # Generate 32 bytes of high-quality entropy (BIP39 standard)
    entropy = :crypto.strong_rand_bytes(32)
    Mnemonic.to_mnemonic(entropy)
  end

  @doc """
  Derive the standard 64-byte BIP39 master seed from a mnemonic:
  `PBKDF2-HMAC-SHA512(mnemonic, "mnemonic", 2048)`. The mnemonic is NFKD-normalized
  per the BIP39 spec.
  """
  @spec master_seed_from_mnemonic(String.t()) :: binary()
  def master_seed_from_mnemonic(mnemonic) when is_binary(mnemonic) do
    normalized_mnemonic = :unicode.characters_to_nfkd_binary(mnemonic)
    :crypto.pbkdf2_hmac(:sha512, normalized_mnemonic, "mnemonic", 2048, 64)
  end

  @doc """
  Derive the post-quantum keypairs from a mnemonic phrase.

  Verifies the BIP39 checksum first, then derives the 64-byte master seed and
  the per-algorithm keypairs. This is the entry point for wallet recovery.
  """
  @spec derive_keys_from_mnemonic(String.t()) :: {:ok, map()} | {:error, term()}
  def derive_keys_from_mnemonic(mnemonic) when is_binary(mnemonic) do
    with {:ok, _entropy} <- Mnemonic.from_mnemonic(mnemonic) do
      mnemonic
      |> master_seed_from_mnemonic()
      |> derive_keys_from_seed()
    end
  end

  @doc """
  Derive cryptographic keys from a binary master seed (the 64-byte BIP39 seed
  from `master_seed_from_mnemonic/2`). Returns all three post-quantum keypairs.

  For wallet recovery from a phrase, prefer `derive_keys_from_mnemonic/2`, which
  also verifies the checksum and applies the BIP39 PBKDF2 step.
  """
  @spec derive_keys_from_seed(binary()) ::
          {:ok,
           %{
             dilithium: Crypto.keypair(),
             falcon: Crypto.keypair(),
             sphincs: Crypto.keypair()
           }}
          | {:error, String.t()}
  def derive_keys_from_seed(master_seed) do
    try do
      # Use the crypto module's deterministic key generation
      dilithium_keys = Crypto.generate_dilithium_keypair_from_seed(master_seed)
      falcon_keys = Crypto.generate_falcon_keypair_from_seed(master_seed)
      sphincs_keys = Crypto.generate_sphincs_keypair_from_seed(master_seed)

      keys = %{
        dilithium: dilithium_keys,
        falcon: falcon_keys,
        sphincs: sphincs_keys
      }

      {:ok, keys}
    rescue
      error ->
        {:error, "Key derivation failed: #{Exception.message(error)}"}
    end
  end

  @doc """
  Validates a master seed mnemonic.
  """
  def valid_master_seed?(seed_mnemonic) do
    words = String.split(seed_mnemonic, " ")
    length(words) == 24 and Mnemonic.valid_mnemonic?(seed_mnemonic)
  end

  # Note: HKDF functions removed - we now use proper NIF-based deterministic key generation
  # for all post-quantum algorithms to ensure correct key formats

  @doc """
  Recovers keys from a master seed (for testing/verification).
  """
  def recover_keys(seed_mnemonic) do
    derive_keys_from_seed(seed_mnemonic)
  end
end
