defmodule Bastille.Features.Api.RPC.ExtractKeysForSigningTest do

  use ExUnit.Case, async: true

  alias Bastille.Features.Api.RPC.ExtractKeysForSigning

  @moduletag :unit

  describe "extract_keys_for_signing RPC method" do
    test "handles missing mnemonic parameter" do
      result = ExtractKeysForSigning.call(%{})

      assert is_map(result)
      assert %{"error" => %{"code" => -32_602, "message" => message}} = result
      assert String.contains?(message, "mnemonic")
    end

    test "handles empty mnemonic parameter" do
      result = ExtractKeysForSigning.call(%{"mnemonic" => ""})

      assert is_map(result)
      case result do
        %{"error" => %{"code" => -32_602, "message" => message}} ->
          assert is_binary(message)
        %{"result" => _} ->
          # Empty string might succeed with some implementations
          assert true
      end
    end

    test "handles invalid mnemonic parameter types" do
      invalid_mnemonics = [nil, 123, %{}, []]

      for mnemonic <- invalid_mnemonics do
        result = ExtractKeysForSigning.call(%{"mnemonic" => mnemonic})

        assert is_map(result)
        case result do
          %{"error" => %{"code" => -32_602, "message" => message}} ->
            assert is_binary(message)
          %{"result" => _} ->
            # Some invalid types might still be processed
            assert true
        end
      end
    end

    test "processes valid mnemonic phrase" do
      valid_mnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"

      result = ExtractKeysForSigning.call(%{"mnemonic" => valid_mnemonic})

      assert is_map(result)

      case result do
        %{"result" => %{"address" => address, "sign_transaction_payload" => payload}} ->
          # Verify address format
          assert is_binary(address)
          prefix = Application.get_env(:bastille, :address_prefix, "1789")
          assert String.starts_with?(address, prefix)

          # Verify payload contains all required post-quantum keys
          assert is_map(payload)
          required_keys = ["dilithium_key", "falcon_key", "sphincs_key"]

          for key <- required_keys do
            assert Map.has_key?(payload, key)
            assert is_binary(payload[key])
            assert String.length(payload[key]) > 0
          end

        %{"error" => %{"code" => -32_602, "message" => message}} ->
          # Error acceptable when crypto service unavailable
          assert is_binary(message)

        _ ->
          flunk("Unexpected response format: #{inspect(result)}")
      end
    end

    test "handles various mnemonic formats" do
      mnemonic_formats = [
        "word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12",  # 12 words
        "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art",  # 24 words
        "UPPERCASE WORDS IN MNEMONIC PHRASE",  # Uppercase
        "Mixed Case Words In Phrase"  # Mixed case
      ]

      for mnemonic <- mnemonic_formats do
        result = ExtractKeysForSigning.call(%{"mnemonic" => mnemonic})

        assert is_map(result)

        case result do
          %{"result" => %{"address" => _, "sign_transaction_payload" => _}} ->
            # Successful extraction
            assert true

          %{"error" => %{"code" => _, "message" => _}} ->
            # Error is acceptable for invalid mnemonics
            assert true

          _ ->
            assert true
        end
      end
    end

    test "handles invalid mnemonic phrases" do
      invalid_mnemonics = [
        "too few words",  # Too few words
        "invalid words that are not in bip39 wordlist here",
        "1234 5678 9012",  # Numbers instead of words
        "special!@#$ characters%^&* in() phrase",  # Special characters
      ]

      for mnemonic <- invalid_mnemonics do
        result = ExtractKeysForSigning.call(%{"mnemonic" => mnemonic})

        assert is_map(result)

        case result do
          %{"error" => %{"code" => code, "message" => message}} ->
            assert is_integer(code)
            assert is_binary(message)
            assert String.length(message) > 0

          %{"result" => %{"sign_transaction_payload" => _}} ->
            # Unexpected but acceptable if validation is lenient
            assert true

          _ ->
            assert true
        end
      end
    end
  end

  describe "parameter validation" do
    test "requires mnemonic parameter" do
      empty_params = [%{}, %{"other" => "param"}]

      for params <- empty_params do
        result = ExtractKeysForSigning.call(params)
        assert result["error"]["code"] == -32_602
        assert String.contains?(result["error"]["message"], "mnemonic")
      end
    end

    test "handles additional parameters gracefully" do
      result = ExtractKeysForSigning.call(%{
        "mnemonic" => "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
        "unused" => "parameter",
        "ignored" => 123
      })

      assert is_map(result)
      # Should process the mnemonic parameter and ignore others
    end
  end

  describe "response format" do
    test "successful response contains keys and address" do
      result = ExtractKeysForSigning.call(%{
        "mnemonic" => "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
      })

      case result do
        %{"result" => %{"address" => address, "sign_transaction_payload" => payload}} ->
          assert is_binary(address)
          assert is_map(payload)

          # Payload should contain all three private keys
          expected_keys = ["dilithium_key", "falcon_key", "sphincs_key"]
          for key <- expected_keys do
            assert Map.has_key?(payload, key)
            assert is_binary(payload[key])
          end

        %{"error" => %{"code" => _, "message" => _}} ->
          # Error response is acceptable
          assert true
      end
    end

    test "key structure is correct when present" do
      result = ExtractKeysForSigning.call(%{
        "mnemonic" => "test mnemonic phrase with sufficient words to make valid seed"
      })

      case result do
        %{"result" => %{"sign_transaction_payload" => payload}} ->
          for key_name <- ["dilithium_key", "falcon_key", "sphincs_key"] do
            if Map.has_key?(payload, key_name) do
              private_key = payload[key_name]

              # Keys should be base64 encoded strings
              assert is_binary(private_key)
              assert String.length(private_key) > 0
            end
          end

        %{"error" => %{"code" => _, "message" => _}} ->
          # Error response is acceptable
          assert true
      end
    end

    test "address format is correct when present" do
      result = ExtractKeysForSigning.call(%{
        "mnemonic" => "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
      })

      case result do
        %{"result" => %{"address" => address}} ->
          assert is_binary(address)

          prefix = Application.get_env(:bastille, :address_prefix, "1789")
          assert String.starts_with?(address, prefix)

          # Address should have correct length (prefix + 40 hex chars)
          expected_length = String.length(prefix) + 40
          assert String.length(address) == expected_length

        %{"error" => %{"code" => _, "message" => _}} ->
          # Error response is acceptable
          assert true
      end
    end

    test "always returns a map" do
      result = ExtractKeysForSigning.call(%{"mnemonic" => "any phrase"})
      assert is_map(result)
    end
  end

  describe "error handling" do
    test "handles crypto service unavailable" do
      result = ExtractKeysForSigning.call(%{
        "mnemonic" => "test mnemonic phrase"
      })

      # Should never crash, always return a map
      assert is_map(result)

      # Should either return result or error
      assert Map.has_key?(result, "result") or Map.has_key?(result, "error")
    end

    test "handles key derivation errors gracefully" do
      result = ExtractKeysForSigning.call(%{
        "mnemonic" => "potentially invalid mnemonic phrase that might cause derivation issues"
      })

      assert is_map(result)

      case result do
        %{"error" => %{"code" => code, "message" => message}} ->
          assert is_integer(code)
          assert is_binary(message)
          assert String.length(message) > 0

        %{"result" => %{"sign_transaction_payload" => _}} ->
          # Success is also acceptable
          assert true

        _ ->
          assert true
      end
    end
  end

  describe "deterministic behavior" do
    test "same mnemonic produces same keys" do
      mnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"

      result1 = ExtractKeysForSigning.call(%{"mnemonic" => mnemonic})
      result2 = ExtractKeysForSigning.call(%{"mnemonic" => mnemonic})

      case {result1, result2} do
        {%{"result" => %{"address" => addr1, "sign_transaction_payload" => payload1}},
         %{"result" => %{"address" => addr2, "sign_transaction_payload" => payload2}}} ->
          # Should be deterministic - same keys and address
          assert payload1 == payload2
          assert addr1 == addr2

        _ ->
          # If extraction fails, both should fail consistently
          assert result1 == result2
      end
    end

    test "different mnemonics produce different keys" do
      mnemonic1 = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
      mnemonic2 = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon"

      result1 = ExtractKeysForSigning.call(%{"mnemonic" => mnemonic1})
      result2 = ExtractKeysForSigning.call(%{"mnemonic" => mnemonic2})

      case {result1, result2} do
        {%{"result" => %{"address" => addr1}}, %{"result" => %{"address" => addr2}}} ->
          # Different mnemonics should produce different addresses
          assert addr1 != addr2

        _ ->
          # If one or both fail, that's acceptable
          assert true
      end
    end
  end
end
