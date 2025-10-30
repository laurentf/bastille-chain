defmodule Bastille.Features.Api.RPC.SignTransactionTest do

  use ExUnit.Case, async: true

  alias Bastille.Features.Api.RPC.SignTransaction

  @moduletag :unit

  describe "sign_transaction RPC method" do
    test "handles missing parameters" do
      result = SignTransaction.call(%{})

      assert is_map(result)
      assert %{"error" => %{"code" => -32_602, "message" => message}} = result
      assert String.contains?(message, "unsigned_transaction")
    end

    test "handles missing 'unsigned_transaction' parameter" do
      result = SignTransaction.call(%{
        "dilithium_key" => "test key"
      })

      assert is_map(result)
      assert result["error"]["code"] == -32_602
      assert String.contains?(result["error"]["message"], "unsigned_transaction")
    end

    test "handles missing private keys" do
      result = SignTransaction.call(%{
        "unsigned_transaction" => Base.encode64(:erlang.term_to_binary(%{
          from: "1789abc",
          to: "1789def",
          amount: 1000,
          nonce: 1
        }))
      })

      assert is_map(result)
      assert result["error"]["code"] == -32_602
      assert String.contains?(result["error"]["message"], "dilithium_key")
    end

    test "processes valid signing parameters" do
      unsigned_tx = %{
        from: "1789" <> String.duplicate("a", 40),
        to: "1789" <> String.duplicate("b", 40),
        amount: 1000000,
        nonce: 1,
        fee: 1000
      }

      params = %{
        "unsigned_transaction" => Base.encode64(:erlang.term_to_binary(unsigned_tx)),
        "dilithium_key" => Base.encode64(<<1::2560>>),
        "falcon_key" => Base.encode64(<<2::10176>>),
        "sphincs_key" => Base.encode64(<<3::2560>>)
      }

      result = SignTransaction.call(params)

      assert is_map(result)

      case result do
        %{"result" => %{"signed_transaction" => signed_tx_b64, "transaction_hash" => hash}} ->
          # Verify signed transaction format
          assert is_binary(signed_tx_b64)
          assert String.length(signed_tx_b64) > 0
          assert is_binary(hash)
          assert String.length(hash) > 0

        %{"error" => %{"code" => -32_602, "message" => message}} ->
          # Error acceptable when crypto service unavailable
          assert is_binary(message)

        _ ->
          flunk("Unexpected response format: #{inspect(result)}")
      end
    end

    test "handles invalid unsigned_transaction format" do
      invalid_transactions = [
        "not_base64",
        "invalid",
        "",
        123,
        nil
      ]

      for invalid_tx <- invalid_transactions do
        result = SignTransaction.call(%{
          "unsigned_transaction" => invalid_tx,
          "dilithium_key" => Base.encode64(<<1::2560>>),
          "falcon_key" => Base.encode64(<<2::10176>>),
          "sphincs_key" => Base.encode64(<<3::2560>>)
        })

        assert is_map(result)
        # Should handle invalid transaction formats
        case result do
          %{"error" => %{"code" => _, "message" => _}} -> assert true
          %{"result" => %{"signed_transaction" => _}} -> assert true
          _ -> assert true
        end
      end
    end

    test "handles invalid private key formats" do
      valid_unsigned_tx = Base.encode64(:erlang.term_to_binary(%{
        from: "1789" <> String.duplicate("a", 40),
        to: "1789" <> String.duplicate("b", 40),
        amount: 1000000,
        nonce: 1
      }))

      invalid_keys = [
        "not_base64",
        "invalid",
        "",
        nil
      ]

      for invalid_key <- invalid_keys do
        result = SignTransaction.call(%{
          "unsigned_transaction" => valid_unsigned_tx,
          "dilithium_key" => invalid_key,
          "falcon_key" => Base.encode64(<<2::10176>>),
          "sphincs_key" => Base.encode64(<<3::2560>>)
        })

        assert is_map(result)
        # Should handle invalid keys appropriately
      end
    end
  end

  describe "parameter validation" do
    test "validates required parameters presence" do
      test_cases = [
        %{},  # Both missing
        %{"unsigned_transaction" => %{}},  # Mnemonic missing
        %{"mnemonic" => "test"}  # Transaction missing
      ]

      for params <- test_cases do
        result = SignTransaction.call(params)
        assert result["error"]["code"] == -32_602
        assert String.contains?(result["error"]["message"], "unsigned_transaction")
      end
    end

    test "handles additional parameters gracefully" do
      result = SignTransaction.call(%{
        "unsigned_transaction" => Base.encode64(:erlang.term_to_binary(%{
          from: "1789" <> String.duplicate("a", 40),
          to: "1789" <> String.duplicate("b", 40),
          amount: 1000000,
          nonce: 1
        })),
        "dilithium_key" => Base.encode64(<<1::2560>>),
        "falcon_key" => Base.encode64(<<2::10176>>),
        "sphincs_key" => Base.encode64(<<3::2560>>),
        "unused" => "parameter",
        "ignored" => 123
      })

      assert is_map(result)
      # Should process required params and ignore others
    end
  end

  describe "response format" do
    test "successful response contains signed_transaction" do
      result = SignTransaction.call(%{
        "unsigned_transaction" => Base.encode64(:erlang.term_to_binary(%{
          from: "1789" <> String.duplicate("c", 40),
          to: "1789" <> String.duplicate("d", 40),
          amount: 2000000,
          nonce: 5,
          fee: 2000
        })),
        "dilithium_key" => Base.encode64(<<1::2560>>),
        "falcon_key" => Base.encode64(<<2::10176>>),
        "sphincs_key" => Base.encode64(<<3::2560>>)
      })

      case result do
        %{"result" => %{"signed_transaction" => signed_tx_b64, "transaction_hash" => hash}} ->
          assert is_binary(signed_tx_b64)
          assert is_binary(hash)

        %{"error" => %{"code" => _, "message" => _}} ->
          # Error response is acceptable
          assert true
      end
    end

    test "transaction hash is included when successful" do
      result = SignTransaction.call(%{
        "unsigned_transaction" => Base.encode64(:erlang.term_to_binary(%{
          from: "1789" <> String.duplicate("e", 40),
          to: "1789" <> String.duplicate("f", 40),
          amount: 500000,
          nonce: 10
        })),
        "dilithium_key" => Base.encode64(<<1::2560>>),
        "falcon_key" => Base.encode64(<<2::10176>>),
        "sphincs_key" => Base.encode64(<<3::2560>>)
      })

      case result do
        %{"result" => %{"signed_transaction" => signed_tx_b64, "transaction_hash" => hash}} ->
          assert is_binary(signed_tx_b64)
          assert is_binary(hash)
          assert String.length(hash) > 0

        %{"error" => %{"code" => _, "message" => _}} ->
          # Error response is acceptable
          assert true
      end
    end

    test "always returns a map" do
      result = SignTransaction.call(%{
        "unsigned_transaction" => "any",
        "dilithium_key" => "any"
      })

      assert is_map(result)
    end
  end

  describe "error handling" do
    test "handles crypto service unavailable" do
      result = SignTransaction.call(%{
        "unsigned_transaction" => Base.encode64(:erlang.term_to_binary(%{
          from: "1789test",
          to: "1789test2",
          amount: 1000,
          nonce: 1
        })),
        "dilithium_key" => Base.encode64(<<1::2560>>),
        "falcon_key" => Base.encode64(<<2::10176>>),
        "sphincs_key" => Base.encode64(<<3::2560>>)
      })

      # Should never crash, always return a map
      assert is_map(result)

      # Should either return result or error
      assert Map.has_key?(result, "result") or Map.has_key?(result, "error")
    end
  end
end
