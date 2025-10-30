defmodule Bastille.Shared.Mnemonic do
  import Bitwise
  @moduledoc """
  🇫🇷 Bastille Mnemonic - French BIP39-style word conversion
  Converts private keys to memorable French words and vice versa.
  """

  # French BIP39 wordlist
  @french_wordlist Path.join(:code.priv_dir(:bastille), "bip39_french.txt")
                   |> File.read!()
                   |> String.split("\n", trim: true)
                   |> Enum.map(fn w -> w |> String.trim() |> :unicode.characters_to_nfc_binary() end)

  defp normalize_word(word) do
    word
    |> String.trim()
    |> :unicode.characters_to_nfc_binary()
  end

  def to_mnemonic(entropy) when is_binary(entropy) and byte_size(entropy) == 32 do
    # BIP39: entropy (32 bytes) + 8 bits checksum = 33 bytes (264 bits)
    checksum = :crypto.hash(:sha256, entropy) |> binary_to_byte()

    entropy_bits = for <<b::1 <- entropy>>, do: b
    checksum_bits = for i <- 0..7, do: (checksum >>> (7-i)) &&& 1

    (entropy_bits ++ checksum_bits)
    |> Enum.chunk_every(11)
    |> Enum.map(&bits_to_word_index/1)
    |> Enum.map_join(" ", &Enum.at(@french_wordlist, &1))
  end

  def from_mnemonic(mnemonic) when is_binary(mnemonic) do
    with {:ok, words} <- parse_and_validate_words(mnemonic),
         {:ok, indices} <- words_to_indices(words) do
      indices_to_entropy(indices)
    end
  end

  # Pipeline helpers with pattern matching
  defp parse_and_validate_words(mnemonic) do
    words =
      mnemonic
      |> String.split(" ")
      |> Enum.map(&normalize_word/1)

    case length(words) do
      24 -> {:ok, words}
      n -> {:error, "Mnemonic must be 24 words, got #{n}"}
    end
  end

  defp words_to_indices(words) do
    indices = Enum.map(words, &find_word_index/1)

    if Enum.any?(indices, &is_nil/1) do
      {:error, "Invalid word in mnemonic"}
    else
      {:ok, indices}
    end
  end

  defp indices_to_entropy(indices) do
    bits =
      indices
      |> Enum.flat_map(&index_to_bits/1)
      |> Enum.split(256)
      |> elem(0)  # Take first 256 bits (entropy)

    entropy =
      bits
      |> Enum.chunk_every(8)
      |> Enum.map(&bits_to_byte/1)
      |> :binary.list_to_bin()

    {:ok, entropy}
  end

  # Helpers with guards and pattern matching
  defp binary_to_byte(<<byte, _rest::binary>>), do: byte

  defp bits_to_word_index(bits) do
    Enum.reduce(bits, 0, fn bit, acc -> (acc <<< 1) ||| bit end)
  end

  defp find_word_index(word) do
    Enum.find_index(@french_wordlist, &(&1 == word))
  end

  defp index_to_bits(index) do
    for i <- 10..0//-1, do: (index >>> i) &&& 1
  end

  defp bits_to_byte(bits) do
    Enum.reduce(bits, 0, fn bit, acc -> (acc <<< 1) ||| bit end)
  end

  def valid_mnemonic?(mnemonic_string) when is_binary(mnemonic_string) do
    words = String.split(mnemonic_string, " ")
    words = Enum.map(words, fn w -> w |> String.trim() |> :unicode.characters_to_nfc_binary() end)
    length(words) >= 12 and Enum.all?(words, fn word -> Enum.member?(@french_wordlist, word) end)
  end



  def wordlist, do: @french_wordlist
end
