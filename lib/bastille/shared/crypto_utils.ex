defmodule Bastille.Shared.CryptoUtils do
  @moduledoc """
  Basic cryptographic utilities for the Bastille blockchain.

  Provides essential hash functions and conversion utilities:
  - SHA-256 hashing
  - Hexadecimal conversion
  - Random byte generation

  For Bastille-specific mining operations, see Bastille.Features.Mining.Mining.
  """

  @doc """
  Computes SHA-256 hash of the given data.
  """
  @spec sha256(iodata()) :: binary()
  def sha256(data) do
    :crypto.hash(:sha256, data)
  end

  @doc """
  Computes double SHA-256 hash (Bitcoin-style).
  """
  @spec double_sha256(iodata()) :: binary()
  def double_sha256(data) do
    data
    |> sha256()
    |> sha256()
  end

  @doc """
  Computes RIPEMD-160 hash.
  """
  @spec ripemd160(iodata()) :: binary()
  def ripemd160(data) do
    :crypto.hash(:ripemd160, data)
  end

  @doc """
  Computes hash160 (RIPEMD-160 of SHA-256).
  """
  @spec hash160(iodata()) :: binary()
  def hash160(data) do
    data
    |> sha256()
    |> ripemd160()
  end

  @doc """
  Converts binary hash to hexadecimal string.
  """
  @spec to_hex(binary()) :: String.t()
  def to_hex(hash) do
    Base.encode16(hash, case: :lower)
  end

  @doc """
  Converts hexadecimal string to binary hash.
  """
  @spec from_hex(String.t()) :: binary()
  def from_hex(hex_string) do
    Base.decode16!(hex_string, case: :mixed)
  end

  @doc """
  Generates a random hash of specified byte length.
  """
  @spec random(pos_integer()) :: binary()
  def random(byte_length \\ 32) do
    :crypto.strong_rand_bytes(byte_length)
  end
end
