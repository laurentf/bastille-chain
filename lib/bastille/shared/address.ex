defmodule Bastille.Shared.Address do
  @moduledoc """
  Bastille address validation utilities.

  Standard Format:
  - All addresses start with configured prefix (e.g., "f789" for test, "1789" for prod)
  - Followed by 40 lowercase hex characters
  - Total length: 44 characters (same for both environments)
  - All characters are valid hexadecimal (0-9, a-f)
  - Example: "f789abc123def456789..." (test) or "1789abc123def456789..." (prod)

  Note: Address generation is handled by `Bastille.Shared.Crypto.generate_bastille_address/1`.
  This module focuses on validation and format utilities.
  """

  @type t :: String.t()

  # REMOVED: generate/0 - Use Crypto.generate_bastille_address/1 instead
  # REMOVED: from_public_key/1 - Use Crypto.generate_bastille_address/1 instead

  @doc """
  Get the configured address prefix from application config.
  """
  @spec get_prefix() :: String.t()
  def get_prefix do
    Application.get_env(:bastille, :address_prefix, "1789")
  end

  @doc """
  Get the expected address length based on configured prefix.
  """
  @spec get_address_length() :: non_neg_integer()
  def get_address_length do
    String.length(get_prefix()) + 40
  end

  @doc """
  Validate if string is a valid Bastille address format.

  Validates the configured prefix + 40 hex format used by Crypto module.

  ## Examples
      iex> Bastille.Shared.Address.valid?("f789abc123def456789012345678901234567890")
      true  # In test environment
      iex> Bastille.Shared.Address.valid?("1789abc123def456789012345678901234567890")
      true  # In prod environment
      iex> Bastille.Shared.Address.valid?("1234InvalidAddress")
      false
  """
  @spec valid?(String.t()) :: boolean()
  def valid?(address) when is_binary(address) do
    prefix = get_prefix()
    expected_length = get_address_length()

    with true <- String.length(address) == expected_length,
         true <- String.starts_with?(address, prefix),
         hex_part <- String.slice(address, String.length(prefix)..-1//1),
         true <- String.length(hex_part) == 40,
         true <- valid_hex_lowercase?(hex_part) do
      true
    else
      _ -> false
    end
  end
  def valid?(_), do: false

  @doc """
  Get the zero address (for genesis or special purposes).
  """
  @spec zero() :: t()
  def zero do
    prefix = get_prefix()
    prefix <> String.duplicate("0", 40)
  end

  @doc """
  Get address format information.
  """
  @spec get_format_info() :: map()
  def get_format_info do
    prefix = get_prefix()
    %{
      prefix: prefix,
      total_length: get_address_length(),
      hex_length: 40,
      example: prefix <> String.duplicate("a", 40)
    }
  end

  # Private functions

  defp valid_hex_lowercase?(hex_string) do
    case Base.decode16(hex_string, case: :lower) do
      {:ok, _} -> true
      :error -> false
    end
  end

  # REMOVED: All Base58 encoding/decoding functions
  # REMOVED: create_address_with_checksum/1
  # REMOVED: checksum validation (not compatible with Crypto module format)


end
