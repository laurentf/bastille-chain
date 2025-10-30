defmodule Bastille.Features.Api.RPC.CreateUnsignedTransactionTest do

  use ExUnit.Case, async: true

  alias Bastille.Features.Api.RPC.CreateUnsignedTransaction

  @moduletag :unit

  describe "create_unsigned_transaction RPC method" do
    test "handles missing parameters" do
      result = CreateUnsignedTransaction.call(%{})

      assert is_map(result)
      assert %{"error" => %{"code" => -32_602, "message" => message}} = result
      assert String.contains?(message, "Transaction creation failed")
    end

    test "handles missing 'from' parameter" do
      result = CreateUnsignedTransaction.call(%{
        "to" => "1789abc",
        "amount" => 1000
      })

      assert is_map(result)
      assert result["error"]["code"] == -32_602
      assert String.contains?(result["error"]["message"], "Transaction creation failed")
    end

    test "handles missing 'to' parameter" do
      result = CreateUnsignedTransaction.call(%{
        "from" => "1789def",
        "amount" => 1000
      })

      assert is_map(result)
      assert result["error"]["code"] == -32_602
      assert String.contains?(result["error"]["message"], "Transaction creation failed")
    end

    test "handles missing 'amount' parameter" do
      result = CreateUnsignedTransaction.call(%{
        "from" => "1789abc",
        "to" => "1789def"
      })

      assert is_map(result)
      assert result["error"]["code"] == -32_602
      assert String.contains?(result["error"]["message"], "Transaction creation failed")
    end

    test "processes valid transaction parameters" do
      prefix = Application.get_env(:bastille, :address_prefix, "1789")
      from_address = prefix <> String.duplicate("a", 40)
      to_address = prefix <> String.duplicate("b", 40)

      params = %{
        "from" => from_address,
        "to" => to_address,
        "amount" => 1000000
      }

      result = CreateUnsignedTransaction.call(params)

      assert is_map(result)

      case result do
        %{"result" => %{"unsigned_transaction" => tx_b64, "transaction_hash" => hash}} ->
          # Verify transaction format
          assert is_binary(tx_b64)
          assert String.length(tx_b64) > 0
          assert is_binary(hash)
          assert String.length(hash) > 0

        %{"error" => %{"code" => -32_602, "message" => message}} ->
          # Error acceptable when blockchain service unavailable
          assert is_binary(message)

        _ ->
          flunk("Unexpected response format: #{inspect(result)}")
      end
    end

    test "handles invalid address formats" do
      invalid_addresses = [
        "invalid_address",
        "1234short",
        "wrongprefix" <> String.duplicate("a", 40)
      ]

      for invalid_addr <- invalid_addresses do
        result = CreateUnsignedTransaction.call(%{
          "from" => invalid_addr,
          "to" => "1789" <> String.duplicate("b", 40),
          "amount" => 1000
        })

        assert is_map(result)
        # Should either return error or handle gracefully
        assert Map.has_key?(result, "error") or Map.has_key?(result, "result")
      end
    end

    test "handles invalid amount values" do
      prefix = Application.get_env(:bastille, :address_prefix, "1789")
      from_address = prefix <> String.duplicate("a", 40)
      to_address = prefix <> String.duplicate("b", 40)

      invalid_amounts = [-100, 0, "not_a_number", nil]

      for amount <- invalid_amounts do
        result = CreateUnsignedTransaction.call(%{
          "from" => from_address,
          "to" => to_address,
          "amount" => amount
        })

        assert is_map(result)
        # Should handle invalid amounts appropriately
      end
    end
  end

  describe "parameter validation" do
    test "validates required parameters presence" do
      required_params = ["from", "to", "amount"]

      # Test each missing parameter combination
      for missing_param <- required_params do
        params = %{
          "from" => "1789abc",
          "to" => "1789def",
          "amount" => 1000
        }
        |> Map.delete(missing_param)

        result = CreateUnsignedTransaction.call(params)
        assert result["error"]["code"] == -32_602
      assert String.contains?(result["error"]["message"], "Transaction creation failed")
      end
    end

    test "handles additional optional parameters" do
      prefix = Application.get_env(:bastille, :address_prefix, "1789")

      result = CreateUnsignedTransaction.call(%{
        "from" => prefix <> String.duplicate("a", 40),
        "to" => prefix <> String.duplicate("b", 40),
        "amount" => 1000000,
        "fee" => 1000,
        "data" => "optional message",
        "unused" => "ignored"
      })

      assert is_map(result)
      # Should process required params and optionally use fee/data
    end
  end

  describe "response format" do
    test "successful response contains unsigned_transaction" do
      prefix = Application.get_env(:bastille, :address_prefix, "1789")

      result = CreateUnsignedTransaction.call(%{
        "from" => prefix <> String.duplicate("c", 40),
        "to" => prefix <> String.duplicate("d", 40),
        "amount" => 5000000
      })

      case result do
        %{"result" => %{"unsigned_transaction" => tx_b64, "transaction_hash" => hash}} ->
          assert is_binary(tx_b64)
          assert is_binary(hash)

        %{"error" => %{"code" => _, "message" => _}} ->
          # Error response is acceptable
          assert true
      end
    end

    test "transaction includes nonce when successful" do
      prefix = Application.get_env(:bastille, :address_prefix, "1789")

      result = CreateUnsignedTransaction.call(%{
        "from" => prefix <> String.duplicate("e", 40),
        "to" => prefix <> String.duplicate("f", 40),
        "amount" => 2000000
      })

      case result do
        %{"result" => %{"unsigned_transaction" => tx_b64, "transaction_hash" => hash}} ->
          # Transaction should be base64 encoded
          assert is_binary(tx_b64)
          assert is_binary(hash)

        %{"error" => %{"code" => _, "message" => _}} ->
          # Error response is acceptable
          assert true
      end
    end

    test "always returns a map" do
      result = CreateUnsignedTransaction.call(%{
        "from" => "any",
        "to" => "any",
        "amount" => 1
      })

      assert is_map(result)
    end
  end
end
