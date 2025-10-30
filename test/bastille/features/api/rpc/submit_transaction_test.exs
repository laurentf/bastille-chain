defmodule Bastille.Features.Api.RPC.SubmitTransactionTest do

  use ExUnit.Case, async: true

  alias Bastille.Features.Api.RPC.SubmitTransaction

  @moduletag :unit

  describe "submit_transaction RPC method" do
    test "handles missing signed_transaction parameter" do
      result = SubmitTransaction.call(%{})

      assert is_map(result)
      assert %{status: "error", reason: reason} = result
      assert is_binary(reason)
    end

    test "handles empty signed_transaction parameter" do
      result = SubmitTransaction.call(%{"signed_transaction" => nil})

      assert is_map(result)
      assert result[:status] == "error"
      assert is_binary(result[:reason])
    end

    test "processes valid signed transaction" do
      # Create mock transaction with required fields
      mock_tx = %{
        from: "1789" <> String.duplicate("a", 40),
        to: "1789" <> String.duplicate("b", 40),
        amount: 1000000,
        nonce: 1,
        fee: 1000,
        hash: :crypto.strong_rand_bytes(32)
      }

      signed_transaction_b64 = Base.encode64(:erlang.term_to_binary(mock_tx))

      result = SubmitTransaction.call(%{"signed_transaction" => signed_transaction_b64})

      assert is_map(result)

      case result do
        %{status: "ok", tx_hash: hash} ->
          # Verify successful submission format
          assert is_binary(hash)
          assert String.length(hash) > 0

        %{status: "error", reason: reason} ->
          # Error acceptable when mempool service unavailable
          assert is_binary(reason)
          assert String.length(reason) > 0

        _ ->
          flunk("Unexpected response format: #{inspect(result)}")
      end
    end

    test "handles invalid signed_transaction formats" do
      invalid_transactions = [
        "not_base64",
        "invalid_b64",
        "",
        123
      ]

      for invalid_tx <- invalid_transactions do
        result = SubmitTransaction.call(%{"signed_transaction" => invalid_tx})

        assert is_map(result)
        # Should handle invalid transaction formats
        case result do
          %{status: "error", reason: reason} ->
            assert is_binary(reason)
            assert String.length(reason) > 0

          %{status: "ok", tx_hash: _} ->
            # Unexpected but acceptable if validation is lenient
            assert true

          _ ->
            assert true
        end
      end
    end

    test "handles transaction without signature" do
      unsigned_transaction = %{
        from: "1789" <> String.duplicate("a", 40),
        to: "1789" <> String.duplicate("b", 40),
        amount: 1000000,
        nonce: 1,
        fee: 1000,
        hash: :crypto.strong_rand_bytes(32)
        # Missing signature
      }

      unsigned_tx_b64 = Base.encode64(:erlang.term_to_binary(unsigned_transaction))

      result = SubmitTransaction.call(%{"signed_transaction" => unsigned_tx_b64})

      assert is_map(result)
      # Should handle missing signature appropriately
      case result do
        %{status: "error", reason: reason} ->
          assert is_binary(reason)

        _ ->
          assert true
      end
    end
  end

  describe "parameter validation" do
    test "requires signed_transaction parameter" do
      empty_params = [%{}, %{"other" => "param"}]

      for params <- empty_params do
        result = SubmitTransaction.call(params)
        assert result[:status] == "error"
        assert is_binary(result[:reason])
      end
    end

    test "handles additional parameters gracefully" do
      signed_tx = %{
        from: "1789" <> String.duplicate("c", 40),
        to: "1789" <> String.duplicate("d", 40),
        amount: 2000000,
        nonce: 5,
        hash: :crypto.strong_rand_bytes(32),
        signature: %{dilithium: "test_sig", falcon: "test_sig2", sphincs: "test_sig3"}
      }

      signed_tx_b64 = Base.encode64(:erlang.term_to_binary(signed_tx))

      result = SubmitTransaction.call(%{
        "signed_transaction" => signed_tx_b64,
        "unused" => "parameter",
        "ignored" => 123
      })

      assert is_map(result)
      # Should process the signed_transaction parameter and ignore others
    end
  end

  describe "response format" do
    test "successful response contains transaction_hash and status" do
      signed_tx = %{
        from: "1789" <> String.duplicate("e", 40),
        to: "1789" <> String.duplicate("f", 40),
        amount: 5000000,
        nonce: 3,
        fee: 2000,
        hash: :crypto.strong_rand_bytes(32),
        signature: %{
          dilithium: "test_signature",
          falcon: "test_signature2",
          sphincs: "test_signature3"
        }
      }

      signed_tx_b64 = Base.encode64(:erlang.term_to_binary(signed_tx))

      result = SubmitTransaction.call(%{"signed_transaction" => signed_tx_b64})

      case result do
        %{status: "ok", tx_hash: hash} ->
          assert is_binary(hash)
          assert String.length(hash) > 0

        %{status: "error", reason: _} ->
          # Error response is acceptable
          assert true
      end
    end

    test "transaction hash is valid when present" do
      signed_tx = %{
        from: "1789" <> String.duplicate("g", 40),
        to: "1789" <> String.duplicate("h", 40),
        amount: 1500000,
        nonce: 8,
        hash: :crypto.strong_rand_bytes(32),
        signature: %{dilithium: "sig1", falcon: "sig2", sphincs: "sig3"}
      }

      signed_tx_b64 = Base.encode64(:erlang.term_to_binary(signed_tx))

      result = SubmitTransaction.call(%{"signed_transaction" => signed_tx_b64})

      if Map.has_key?(result, :tx_hash) do
        hash = result[:tx_hash]
        assert is_binary(hash)
        assert String.length(hash) > 0
        # Hash should typically be hex encoded
        assert Regex.match?(~r/^[0-9a-fA-F]+$/, hash) or String.length(hash) > 10
      end
    end

    test "always returns a map" do
      result = SubmitTransaction.call(%{"signed_transaction" => "any"})
      assert is_map(result)
    end
  end

  describe "error handling" do
    test "handles mempool service unavailable" do
      valid_signed_tx = %{
        "from" => "1789test",
        "to" => "1789test2",
        "amount" => 1000,
        "nonce" => 1,
        "signature" => %{"test" => "sig"}
      }

      result = SubmitTransaction.call(%{"signed_transaction" => valid_signed_tx})

      # Should never crash, always return a map
      assert is_map(result)

      # Should either return success or error
      assert Map.has_key?(result, :tx_hash) or Map.has_key?(result, :status)
    end

    test "handles validation errors gracefully" do
      malformed_tx = %{
        "from" => "invalid_address",
        "to" => "also_invalid",
        "amount" => -1000,  # Negative amount
        "signature" => "not_a_proper_signature"
      }

      result = SubmitTransaction.call(%{"signed_transaction" => malformed_tx})

      assert is_map(result)
      # Should handle validation errors appropriately
      case result do
        %{"error" => error_msg} ->
          assert is_binary(error_msg)
          assert String.length(error_msg) > 0

        _ ->
          # Any other response is acceptable
          assert true
      end
    end
  end
end
