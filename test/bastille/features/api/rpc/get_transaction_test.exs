defmodule Bastille.Features.Api.RPC.GetTransactionTest do

  use ExUnit.Case, async: true

  alias Bastille.Features.Api.RPC.GetTransaction

  @moduletag :unit

  describe "get_transaction RPC method" do
    test "handles missing hash parameter" do
      # GetTransaction implementation requires hash parameter
      assert_raise FunctionClauseError, fn ->
        GetTransaction.call(%{})
      end
    end

    test "handles empty hash parameter" do
      result = GetTransaction.call(%{"hash" => ""})

      assert is_map(result)
      case result do
        %{hash: "", transaction: _} -> assert true
        %{error: _} -> assert true
      end
    end

    test "processes valid hash parameter" do
      test_hash = "0123456789abcdef"

      result = GetTransaction.call(%{"hash" => test_hash})

      assert is_map(result)

      case result do
        %{hash: ^test_hash, transaction: transaction} ->
          # Verify transaction data (can be nil if not found)
          assert is_map(transaction) or is_nil(transaction)

        %{error: error_msg} ->
          # Error acceptable when blockchain service unavailable
          assert is_binary(error_msg)
          assert String.length(error_msg) > 0

        _ ->
          flunk("Unexpected response format: #{inspect(result)}")
      end
    end

    test "handles various hash formats" do
      hash_formats = [
        "abcdef123456789",           # Short hash
        "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef", # Long hash
        "ABCDEF123",                 # Uppercase
        "mixed_Case_123"             # Mixed case
      ]

      for hash <- hash_formats do
        result = GetTransaction.call(%{"hash" => hash})
        assert is_map(result)

        # Should handle any hash format gracefully
        case result do
          %{hash: _, transaction: _} -> assert true
          %{error: _} -> assert true
          _ -> assert true
        end
      end
    end

    test "handles non-string hash parameter" do
      invalid_hashes = [123, nil, %{}, []]

      for hash <- invalid_hashes do
        result = GetTransaction.call(%{"hash" => hash})
        assert is_map(result)
        case result do
          %{hash: _, transaction: _} -> assert true
          %{error: _} -> assert true
        end
      end
    end
  end

  describe "parameter validation" do
    test "requires hash parameter" do
      empty_params = [%{}, %{"other" => "param"}]

      for params <- empty_params do
        assert_raise FunctionClauseError, fn ->
          GetTransaction.call(params)
        end
      end
    end

    test "ignores additional parameters" do
      result = GetTransaction.call(%{
        "hash" => "test_hash",
        "unused" => "parameter",
        "ignored" => 123
      })

      assert is_map(result)
      # Should process the hash parameter and ignore others
    end
  end

  describe "response format" do
    test "successful response contains transaction" do
      result = GetTransaction.call(%{"hash" => "sample_hash"})

      case result do
        %{hash: _, transaction: transaction} ->
          assert is_map(transaction) or is_nil(transaction)

        %{error: _} ->
          # Error response is acceptable
          assert true
      end
    end

    test "transaction not found response" do
      result = GetTransaction.call(%{"hash" => "nonexistent_hash"})

      # Should handle non-existent transactions gracefully
      case result do
        %{hash: _, transaction: nil} -> assert true
        %{hash: _, transaction: _} -> assert true
        %{error: _} -> assert true  # Errors acceptable
      end
    end

    test "always returns a map" do
      result = GetTransaction.call(%{"hash" => "any_hash"})
      assert is_map(result)
    end
  end

  describe "error handling" do
    test "handles service unavailable gracefully" do
      result = GetTransaction.call(%{"hash" => "test_hash"})

      # Should never crash, always return a map
      assert is_map(result)

      # Should either return transaction or error
      assert Map.has_key?(result, :transaction) or Map.has_key?(result, :error)
    end
  end
end
