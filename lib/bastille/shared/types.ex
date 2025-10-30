defmodule Bastille.Shared.Types do
@moduledoc """
Shared types for the Bastille application.

This module centralizes all type definitions used across multiple features.
"""

  # Blockchain base types
  @type block_height :: non_neg_integer()
  @type block_hash :: binary()
  @type transaction_hash :: binary()
  @type address :: String.t()
  @type private_key :: binary()
  @type public_key :: binary()
  @type signature :: binary()

# Economics types (from tokenomics/)
  @type amount_juillet :: non_neg_integer()
  @type amount_bast :: float()
  @type fee_amount :: non_neg_integer()

  # Cryptographic types
  @type signature_type :: :dilithium | :falcon | :sphincs | :coinbase
  @type crypto_keys :: %{
    dilithium: binary(),
    falcon: binary(),
    sphincs: binary()
  }

# Difficulty types
  @type difficulty :: non_neg_integer()
  @type nonce :: non_neg_integer()

  # P2P types
  @type peer_address :: String.t()
  @type peer_port :: non_neg_integer()
  @type node_id :: String.t()

# Common result types
  @type result(success, error) :: {:ok, success} | {:error, error}
  @type blockchain_result(data) :: result(data, atom() | String.t())
end
