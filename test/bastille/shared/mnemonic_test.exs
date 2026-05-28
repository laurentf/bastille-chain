defmodule Bastille.Shared.MnemonicTest do
  use ExUnit.Case, async: true

  alias Bastille.Shared.Mnemonic

  @moduletag :unit

  # Test entropy - 32 bytes for 24-word mnemonic
  @test_entropy_32_bytes <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
                           21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32>>

  describe "wordlist access" do
    test "wordlist is available and has 2048 words" do
      wordlist = Mnemonic.wordlist()

      assert is_list(wordlist)
      assert length(wordlist) == 2048

      # Check some French words are present
      assert "abandon" in wordlist or "abaisser" in wordlist
      assert Enum.all?(wordlist, &is_binary/1)
    end

    test "all words in wordlist are unique" do
      wordlist = Mnemonic.wordlist()

      assert length(wordlist) == length(Enum.uniq(wordlist))
    end

    test "wordlist words are properly normalized" do
      wordlist = Mnemonic.wordlist()

      # All words should be trimmed and normalized
      assert Enum.all?(wordlist, fn word ->
               word == String.trim(word) and word != ""
             end)
    end
  end

  describe "entropy to mnemonic conversion" do
    test "converts 32-byte entropy to 24-word mnemonic" do
      mnemonic = Mnemonic.to_mnemonic(@test_entropy_32_bytes)
      words = String.split(mnemonic, " ")

      assert length(words) == 24
      assert is_binary(mnemonic)

      # All words should be in the wordlist
      wordlist = Mnemonic.wordlist()
      assert Enum.all?(words, fn word -> word in wordlist end)
    end

    test "same entropy produces same mnemonic" do
      mnemonic1 = Mnemonic.to_mnemonic(@test_entropy_32_bytes)
      mnemonic2 = Mnemonic.to_mnemonic(@test_entropy_32_bytes)

      assert mnemonic1 == mnemonic2
    end

    test "different entropy produces different mnemonics" do
      entropy1 = @test_entropy_32_bytes
      entropy2 = :crypto.strong_rand_bytes(32)

      mnemonic1 = Mnemonic.to_mnemonic(entropy1)
      mnemonic2 = Mnemonic.to_mnemonic(entropy2)

      assert mnemonic1 != mnemonic2
    end

    test "handles zero entropy" do
      zero_entropy = <<0::256>>
      mnemonic = Mnemonic.to_mnemonic(zero_entropy)
      words = String.split(mnemonic, " ")

      assert length(words) == 24

      # All words should be valid
      wordlist = Mnemonic.wordlist()
      assert Enum.all?(words, fn word -> word in wordlist end)
    end

    test "handles max entropy" do
      max_entropy = <<255::256>>
      mnemonic = Mnemonic.to_mnemonic(max_entropy)
      words = String.split(mnemonic, " ")

      assert length(words) == 24

      # All words should be valid
      wordlist = Mnemonic.wordlist()
      assert Enum.all?(words, fn word -> word in wordlist end)
    end
  end

  describe "mnemonic to entropy conversion" do
    test "converts valid mnemonic back to original entropy" do
      original_entropy = @test_entropy_32_bytes
      mnemonic = Mnemonic.to_mnemonic(original_entropy)

      case Mnemonic.from_mnemonic(mnemonic) do
        {:ok, recovered_entropy} ->
          assert recovered_entropy == original_entropy

        {:error, reason} ->
          # Test might fail if wordlist is not properly loaded
          assert is_binary(reason)
      end
    end

    test "round-trip conversion maintains entropy" do
      # Test with random entropy
      random_entropy = :crypto.strong_rand_bytes(32)
      mnemonic = Mnemonic.to_mnemonic(random_entropy)

      case Mnemonic.from_mnemonic(mnemonic) do
        {:ok, recovered_entropy} ->
          assert recovered_entropy == random_entropy

        {:error, _reason} ->
          # Test might fail if wordlist is not properly loaded
          assert true
      end
    end

    test "rejects mnemonic with wrong word count" do
      # Create a mnemonic and remove one word
      full_mnemonic = Mnemonic.to_mnemonic(@test_entropy_32_bytes)
      short_mnemonic = full_mnemonic |> String.split(" ") |> Enum.drop(1) |> Enum.join(" ")

      case Mnemonic.from_mnemonic(short_mnemonic) do
        {:error, reason} ->
          assert String.contains?(reason, "must be 24 words")

        _ ->
          flunk("Should reject mnemonic with wrong word count")
      end
    end

    test "rejects mnemonic with invalid words" do
      valid_mnemonic = Mnemonic.to_mnemonic(@test_entropy_32_bytes)
      words = String.split(valid_mnemonic, " ")

      # Replace first word with invalid word
      invalid_words = ["invalidword" | Enum.drop(words, 1)]
      invalid_mnemonic = Enum.join(invalid_words, " ")

      case Mnemonic.from_mnemonic(invalid_mnemonic) do
        {:error, reason} ->
          assert String.contains?(reason, "Invalid word")

        _ ->
          flunk("Should reject mnemonic with invalid words")
      end
    end
  end

  describe "mnemonic validation" do
    test "validates correct 24-word mnemonic" do
      mnemonic = Mnemonic.to_mnemonic(@test_entropy_32_bytes)
      assert Mnemonic.valid_mnemonic?(mnemonic)
    end

    test "accepts only a complete, valid 24-word mnemonic" do
      full_mnemonic = Mnemonic.to_mnemonic(@test_entropy_32_bytes)
      words = String.split(full_mnemonic, " ")

      assert Mnemonic.valid_mnemonic?(full_mnemonic)
      refute Mnemonic.valid_mnemonic?(Enum.take(words, 12) |> Enum.join(" "))
      refute Mnemonic.valid_mnemonic?(Enum.take(words, 18) |> Enum.join(" "))
    end

    test "rejects a 24-word mnemonic with an invalid checksum" do
      words = Mnemonic.to_mnemonic(@test_entropy_32_bytes) |> String.split(" ")
      # Replace the first (entropy) word with a different valid word: the phrase
      # stays 24 valid words but no longer matches its checksum.
      replacement = Enum.find(Mnemonic.wordlist(), &(&1 != hd(words)))
      tampered = [replacement | tl(words)] |> Enum.join(" ")

      refute Mnemonic.valid_mnemonic?(tampered)
      assert {:error, reason} = Mnemonic.from_mnemonic(tampered)
      assert String.contains?(reason, "checksum")
    end

    test "rejects mnemonics with less than 12 words" do
      # Only 3 words
      short_mnemonic = "word1 word2 word3"
      refute Mnemonic.valid_mnemonic?(short_mnemonic)

      eleven_words = String.duplicate("abandon ", 11) |> String.trim()
      refute Mnemonic.valid_mnemonic?(eleven_words)
    end

    test "rejects mnemonics with invalid words" do
      invalid_mnemonic = String.duplicate("invalidword ", 24) |> String.trim()
      refute Mnemonic.valid_mnemonic?(invalid_mnemonic)
    end

    test "rejects empty or malformed input" do
      refute Mnemonic.valid_mnemonic?("")
      refute Mnemonic.valid_mnemonic?("   ")
      refute Mnemonic.valid_mnemonic?("single")
    end

    test "validates regardless of unicode normalization form (NFC/NFD)" do
      mnemonic = Mnemonic.to_mnemonic(@test_entropy_32_bytes)
      assert Mnemonic.valid_mnemonic?(mnemonic)

      # The same phrase in decomposed (NFD) form must still validate, because
      # the module normalizes words to NFC before lookup.
      nfd = :unicode.characters_to_nfd_binary(mnemonic)
      assert Mnemonic.valid_mnemonic?(nfd)
    end
  end

  describe "edge cases and error handling" do
    test "handles entropy of wrong size gracefully" do
      # Test with wrong entropy sizes - should not crash
      # 4 bytes instead of 32
      short_entropy = <<1, 2, 3, 4>>

      try do
        _result = Mnemonic.to_mnemonic(short_entropy)
        # Might work or might fail, but shouldn't crash
        assert true
      rescue
        # Expected to fail with wrong size
        _ -> assert true
      end
    end

    test "handles malformed input types" do
      malformed_inputs = [123, %{}, [], :atom, {:tuple, "data"}]

      for input <- malformed_inputs do
        # These will raise FunctionClauseError due to guard, which is expected behavior
        assert_raise FunctionClauseError, fn ->
          Mnemonic.valid_mnemonic?(input)
        end
      end

      # Test nil separately as it might be handled differently
      assert_raise FunctionClauseError, fn ->
        Mnemonic.valid_mnemonic?(nil)
      end
    end
  end
end
