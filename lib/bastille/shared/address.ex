defmodule Bastille.Shared.Address do
  @moduledoc """
  Bastille address validation, canonicalization, and display utilities.

  ## Format

  An address is `<prefix> <40-hex>` :
  - **prefix** : configured per environment (e.g. `"1789"` mainnet,
    `"f789"` testnet). Always lowercase.
  - **40 hex chars** : derived from `SHA256(dilithium_pub || falcon_pub ||
    sphincs_pub)`, first 20 bytes.

  Total length: 44 chars.

  ## Canonical vs display form

  - **Canonical form** : prefix + 40 lowercase hex. This is the form used
    everywhere on-chain (State storage keys, transaction `from`/`to`
    fields, hash inputs, etc.). It is what `Crypto.generate_bastille_address/1`
    produces. Always use `canonical/1` to normalize before storage or
    comparison.
  - **Display form** : same prefix + 40 hex with **mixed case** acting as
    a checksum (EIP-55-inspired, SHA-256 based). Wallets and UIs should
    show this form to users to enable typo detection on copy/paste.

  ## Accepted input forms (cf. `valid?/1`)

  In keeping with EIP-55, three forms are accepted:

  1. **All-lowercase** (canonical) → no checksum required.
  2. **All-uppercase** (legacy / shouty copy/paste) → no checksum required.
  3. **Mixed-case** → the EIP-55-inspired checksum MUST validate, otherwise
     the address is rejected.

  Any other case mix (e.g. lowercase + uppercase + checksum invalid) is
  rejected — that's the whole point: it means a character has been
  altered by a typo.

  ## Algorithm (EIP-55-inspired, with SHA-256)

  For each character at position `i` in the 40-hex part :
  - If the char is a digit `0-9` → keep as is.
  - If the char is a hex letter `a-f` → uppercase it iff the `i`-th
    nibble of `SHA256(prefix <> lowercase_hex)` is ≥ 8.

  We use SHA-256 (instead of Keccak-256 like Ethereum) to avoid pulling in
  a Keccak NIF — the bits of entropy used by the checksum (40 bits, 4 per
  hex letter on average) are tiny compared to either hash's security
  margin.
  """

  alias Bastille.Shared.CryptoUtils

  @type t :: String.t()

  @doc """
  Get the configured address prefix from application config.
  """
  @spec get_prefix() :: String.t()
  def get_prefix do
    Application.get_env(:bastille, :address_prefix, "1789")
  end

  @doc """
  Get the expected address length based on the configured prefix.
  """
  @spec get_address_length() :: non_neg_integer()
  def get_address_length do
    String.length(get_prefix()) + 40
  end

  @doc """
  Validate an address in any accepted form (lowercase / uppercase /
  mixed-case-with-checksum).

  ## Examples
      iex> Bastille.Shared.Address.valid?("f789" <> String.duplicate("a", 40))
      true  # all-lowercase, in test env

      iex> Bastille.Shared.Address.valid?("f789" <> String.duplicate("A", 40))
      true  # all-uppercase, legacy tolerance

      iex> Bastille.Shared.Address.valid?("not-a-real-address")
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
         true <- valid_hex_any_case?(hex_part) do
      validate_case_form(hex_part, prefix)
    else
      _ -> false
    end
  end

  def valid?(_), do: false

  @doc """
  Returns the canonical (lowercase) form of an address. Only addresses
  matching the standard length/prefix shape are downcased — synthetic
  sentinels like `"1789Genesis"` and any non-conforming string are passed
  through unchanged so they remain recognizable by pattern-matching
  consumers.
  """
  @spec canonical(String.t()) :: String.t()
  def canonical(address) when is_binary(address) do
    prefix = get_prefix()
    expected_length = get_address_length()

    cond do
      String.length(address) == expected_length and String.starts_with?(address, prefix) ->
        String.downcase(address)

      true ->
        address
    end
  end

  @doc """
  Returns the EIP-55-inspired mixed-case display form. Input must be a
  valid lowercase address (use `canonical/1` first if unsure).
  """
  @spec with_checksum(String.t()) :: String.t()
  def with_checksum(address) when is_binary(address) do
    prefix = get_prefix()

    case String.starts_with?(address, prefix) do
      true ->
        lowercase = String.downcase(address)
        hex_part = String.slice(lowercase, String.length(prefix)..-1//1)
        prefix <> apply_checksum(hex_part, lowercase)

      false ->
        address
    end
  end

  @doc """
  Check whether a mixed-case address has a valid checksum. All-lowercase
  and all-uppercase addresses return `true` (they are not checksummed but
  are accepted by `valid?/1`).
  """
  @spec valid_checksum?(String.t()) :: boolean()
  def valid_checksum?(address) when is_binary(address) do
    prefix = get_prefix()

    case String.starts_with?(address, prefix) do
      true ->
        hex_part = String.slice(address, String.length(prefix)..-1//1)

        cond do
          all_lowercase_hex?(hex_part) -> true
          all_uppercase_hex?(hex_part) -> true
          true -> address == with_checksum(String.downcase(address))
        end

      false ->
        false
    end
  end

  def valid_checksum?(_), do: false

  @doc """
  Get the zero address (for genesis or burn semantics).
  """
  @spec zero() :: t()
  def zero do
    get_prefix() <> String.duplicate("0", 40)
  end

  @doc """
  Get address format information.
  """
  @spec get_format_info() :: map()
  def get_format_info do
    prefix = get_prefix()
    sample_canonical = prefix <> String.duplicate("a", 40)

    %{
      prefix: prefix,
      total_length: get_address_length(),
      hex_length: 40,
      example_canonical: sample_canonical,
      example_display: with_checksum(sample_canonical)
    }
  end

  # === Private ===

  # Accepts the hex part in any single-case or valid checksum mix.
  defp validate_case_form(hex_part, prefix) do
    cond do
      all_lowercase_hex?(hex_part) -> true
      all_uppercase_hex?(hex_part) -> true
      true -> (prefix <> hex_part) == with_checksum(prefix <> String.downcase(hex_part))
    end
  end

  defp valid_hex_any_case?(hex_string) do
    case Base.decode16(hex_string, case: :mixed) do
      {:ok, _} -> true
      :error -> false
    end
  end

  defp all_lowercase_hex?(hex_string) do
    case Base.decode16(hex_string, case: :lower) do
      {:ok, _} -> true
      :error -> false
    end
  end

  defp all_uppercase_hex?(hex_string) do
    case Base.decode16(hex_string, case: :upper) do
      {:ok, _} -> true
      :error -> false
    end
  end

  # Compute the EIP-55-inspired checksum on a lowercase 40-hex string.
  # `full_lowercase` (prefix+hex) is hashed so the checksum is bound to
  # the network prefix — preventing the same hex from validating across
  # testnet and mainnet.
  defp apply_checksum(hex_part, full_lowercase) do
    hash = CryptoUtils.sha256(full_lowercase)
    hash_hex = Base.encode16(hash, case: :lower)

    hex_part
    |> String.graphemes()
    |> Enum.with_index()
    |> Enum.map(fn {char, i} -> maybe_uppercase(char, String.at(hash_hex, i)) end)
    |> Enum.join()
  end

  # Hex char at position i:
  #   - digit → keep as-is
  #   - a-f and the corresponding hash nibble ≥ 8 → uppercase
  #   - a-f and the corresponding hash nibble < 8 → lowercase
  defp maybe_uppercase(char, _hash_char) when char in ~w(0 1 2 3 4 5 6 7 8 9), do: char
  defp maybe_uppercase(char, hash_char) when char in ~w(a b c d e f) do
    case hash_char in ~w(8 9 a b c d e f) do
      true -> String.upcase(char)
      false -> char
    end
  end
end
