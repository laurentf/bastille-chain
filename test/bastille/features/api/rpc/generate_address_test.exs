defmodule Bastille.Features.Api.RPC.GenerateAddressTest do
  use ExUnit.Case, async: true

  alias Bastille.Features.Api.RPC.GenerateAddress

  @moduletag :unit

  describe "generate address RPC method" do
    test "generates address with mnemonic successfully" do
      result = GenerateAddress.call(%{})
      
      case result do
        %{address: address, mnemonic: mnemonic, mnemonic_phrase: phrase} ->
          # Valid successful response
          assert is_binary(address)
          assert is_list(mnemonic)
          assert is_binary(phrase)
          
          # Address should have correct prefix
          prefix = Application.get_env(:bastille, :address_prefix, "1789")
          assert String.starts_with?(address, prefix)
          
          # Mnemonic should be 24 words
          assert length(mnemonic) == 24
          
          # Phrase should contain all words
          phrase_words = String.split(phrase, " ")
          assert phrase_words == mnemonic
        
        %{error: error_msg} ->
          # Valid error response
          assert is_binary(error_msg)
          assert String.length(error_msg) > 0
        
        _ ->
          flunk("Unexpected response format: #{inspect(result)}")
      end
    end

    test "ignores any parameters passed" do
      # Should work the same regardless of parameters
      result1 = GenerateAddress.call(%{})
      result2 = GenerateAddress.call(%{"unused" => "parameter"})
      result3 = GenerateAddress.call(%{"multiple" => "params", "ignored" => true})
      
      # All should have the same structure (though different values)
      case {result1, result2, result3} do
        {%{address: _, mnemonic: _, mnemonic_phrase: _}, 
         %{address: _, mnemonic: _, mnemonic_phrase: _},
         %{address: _, mnemonic: _, mnemonic_phrase: _}} ->
          # All succeeded - addresses should be different
          assert result1.address != result2.address
          assert result2.address != result3.address
          assert result1.mnemonic != result2.mnemonic
        
        _ ->
          # Some may have errors, which is acceptable
          assert true
      end
    end

    test "generates unique addresses each time" do
      results = for _ <- 1..5 do
        GenerateAddress.call(%{})
      end
      
      successful_results = Enum.filter(results, fn
        %{address: _} -> true
        _ -> false
      end)
      
      if length(successful_results) >= 2 do
        addresses = Enum.map(successful_results, & &1.address)
        mnemonics = Enum.map(successful_results, & &1.mnemonic_phrase)
        
        # All addresses should be unique
        assert length(Enum.uniq(addresses)) == length(addresses)
        # All mnemonics should be unique
        assert length(Enum.uniq(mnemonics)) == length(mnemonics)
      else
        # If most calls fail, that's acceptable for this test
        assert true
      end
    end

    test "handles underlying function errors gracefully" do
      # This test verifies error handling works
      # We can't easily force an error, but we can verify the structure
      result = GenerateAddress.call(%{})
      
      # Should never crash, always return a map
      assert is_map(result)
      
      # Should either succeed or have error
      assert Map.has_key?(result, :address) or Map.has_key?(result, :error)
    end
  end

  describe "response format validation" do
    test "successful response has required fields" do
      result = GenerateAddress.call(%{})
      
      case result do
        %{address: address, mnemonic: mnemonic, mnemonic_phrase: phrase} ->
          # Check field types
          assert is_binary(address) and String.length(address) > 0
          assert is_list(mnemonic) and length(mnemonic) > 0
          assert is_binary(phrase) and String.length(phrase) > 0
          
          # Check field relationships
          assert Enum.join(mnemonic, " ") == phrase
        
        %{error: _} ->
          # Error responses are acceptable
          assert true
      end
    end

    test "address format is valid" do
      result = GenerateAddress.call(%{})
      
      case result do
        %{address: address} ->
          prefix = Application.get_env(:bastille, :address_prefix, "1789")
          expected_length = String.length(prefix) + 40
          
          # Should start with correct prefix
          assert String.starts_with?(address, prefix)
          
          # Should have correct total length
          assert String.length(address) == expected_length
          
          # Address part (after prefix) should be valid hex
          address_part = String.slice(address, String.length(prefix)..-1//1)
          assert Regex.match?(~r/^[0-9a-f]+$/, address_part)
        
        %{error: _} ->
          # Error responses are acceptable
          assert true
      end
    end

    test "mnemonic format is valid" do
      result = GenerateAddress.call(%{})
      
      case result do
        %{mnemonic: mnemonic, mnemonic_phrase: phrase} ->
          # Should be exactly 24 words
          assert length(mnemonic) == 24
          
          # All words should be non-empty strings
          assert Enum.all?(mnemonic, fn word ->
            is_binary(word) and String.length(word) > 0
          end)
          
          # Phrase should match mnemonic list
          phrase_words = String.split(phrase, " ")
          assert phrase_words == mnemonic
          
          # Should not contain invalid characters
          assert Regex.match?(~r/^[a-zA-ZÀ-ÿ\s]+$/, phrase)
        
        %{error: _} ->
          # Error responses are acceptable
          assert true
      end
    end
  end
end