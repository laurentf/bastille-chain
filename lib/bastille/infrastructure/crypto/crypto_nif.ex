defmodule Bastille.Infrastructure.Crypto.CryptoNif do
  @moduledoc """
  Native Implemented Functions (NIFs) for post-quantum cryptography.

  This module provides direct access to Rust-implemented cryptographic functions
  for maximum performance and security.
  """

  use Rustler, otp_app: :bastille, crate: "bastille_crypto"

  # === NIF Status ===

  @doc """
  Check if NIFs are properly loaded.
  """
  def nifs_loaded, do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Get information about available algorithms.
  """
  def get_algorithm_info, do: :erlang.nif_error(:nif_not_loaded)

  # === Dilithium NIFs ===

  @doc """
  Generate a Dilithium2 keypair.
  """
  def dilithium2_keypair, do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Generate a deterministic Dilithium2 keypair from seed.
  """
  def dilithium2_keypair_from_seed(_seed), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Sign a message with Dilithium2.
  """
  def dilithium2_sign(_message, _private_key), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Verify a Dilithium2 signature.
  """
  def dilithium2_verify(_signature, _message, _public_key), do: :erlang.nif_error(:nif_not_loaded)

  # === Falcon NIFs ===

  @doc """
  Generate a Falcon-512 keypair.
  """
  def falcon512_keypair, do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Generate a deterministic Falcon-512 keypair from seed.
  """
  def falcon512_keypair_from_seed(_seed), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Sign a message with Falcon-512.
  """
  def falcon512_sign(_message, _private_key), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Verify a Falcon-512 signature.
  """
  def falcon512_verify(_signature, _message, _public_key), do: :erlang.nif_error(:nif_not_loaded)

  # === SPHINCS+ NIFs ===

  @doc """
  Generate a SPHINCS+-SHAKE-128f keypair.
  """
  def sphincsplus_shake_128f_keypair, do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Generate a deterministic SPHINCS+-SHAKE-128f keypair from seed.
  """
  def sphincsplus_keypair_from_seed(_seed), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Sign a message with SPHINCS+-SHAKE-128f.
  """
  def sphincsplus_shake_128f_sign(_message, _private_key), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Verify a SPHINCS+-SHAKE-128f signature.
  """
  def sphincsplus_shake_128f_verify(_signature, _message, _public_key), do: :erlang.nif_error(:nif_not_loaded)

  # === Blake3 Hash ===

  @doc """
  Compute Blake3 hash of input data.
  """
  def blake3_hash(_data), do: :erlang.nif_error(:nif_not_loaded)
end
