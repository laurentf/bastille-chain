defmodule Bastille.Shared.CryptoUtilsTest do
  use ExUnit.Case, async: true

  alias Bastille.Shared.CryptoUtils

  @moduletag :unit

  describe "SHA256 hashing" do
    test "sha256 produces consistent 32-byte hash" do
      input = "test data"
      hash1 = CryptoUtils.sha256(input)
      hash2 = CryptoUtils.sha256(input)
      
      assert hash1 == hash2
      assert byte_size(hash1) == 32
    end

    test "sha256 with different inputs produces different hashes" do
      hash1 = CryptoUtils.sha256("input1")
      hash2 = CryptoUtils.sha256("input2")
      
      assert hash1 != hash2
      assert byte_size(hash1) == 32
      assert byte_size(hash2) == 32
    end

    test "sha256 with binary data" do
      binary_input = <<1, 2, 3, 4, 5>>
      hash = CryptoUtils.sha256(binary_input)
      
      assert byte_size(hash) == 32
      assert is_binary(hash)
    end

    test "sha256 with list of binaries" do
      inputs = ["part1", "part2", "part3"]
      hash = CryptoUtils.sha256(inputs)
      
      # Should concatenate and hash
      expected = CryptoUtils.sha256("part1part2part3")
      assert hash == expected
      assert byte_size(hash) == 32
    end

    test "sha256 with empty input" do
      hash = CryptoUtils.sha256("")
      
      assert byte_size(hash) == 32
      # SHA256 of empty string is known value
      expected = :crypto.hash(:sha256, "")
      assert hash == expected
    end
  end

  describe "edge cases" do
    test "sha256 with very large input" do
      large_input = String.duplicate("a", 10000)
      hash = CryptoUtils.sha256(large_input)
      
      assert byte_size(hash) == 32
      assert is_binary(hash)
    end

    test "sha256 with unicode characters" do
      unicode_input = "héllo wørld 🌟"
      hash = CryptoUtils.sha256(unicode_input)
      
      assert byte_size(hash) == 32
      assert is_binary(hash)
    end

    test "sha256 deterministic across calls" do
      input = "deterministic test"
      hashes = Enum.map(1..100, fn _ -> CryptoUtils.sha256(input) end)
      
      # All hashes should be identical
      assert Enum.uniq(hashes) |> length() == 1
    end
  end
end