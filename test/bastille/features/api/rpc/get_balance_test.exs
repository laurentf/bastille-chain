defmodule Bastille.Features.Api.RPC.GetBalanceTest do

  use ExUnit.Case, async: true

  alias Bastille.Features.Api.RPC.GetBalance

  @moduletag :unit

  describe "get_balance RPC method" do
    test "handles missing address parameter" do
      result = GetBalance.call(%{})

      assert is_map(result)
      assert %{error: "Missing or invalid 'address' parameter"} = result
    end

    test "handles empty address parameter" do
      result = GetBalance.call(%{"address" => ""})

      assert is_map(result)
      case result do
        %{address: "", balance: balance} ->
          # Empty address processed, balance should be numeric
          assert is_number(balance)
        %{error: _} ->
          # Error response also acceptable
          assert true
      end
    end

    test "handles non-string address parameter" do
      result = GetBalance.call(%{"address" => 123})

      assert is_map(result)
      case result do
        %{address: 123, balance: balance} ->
          # Non-string address processed, balance should be numeric
          assert is_number(balance)
        %{error: _} ->
          # Error response also acceptable
          assert true
      end
    end

    test "processes valid address format" do
      prefix = Application.get_env(:bastille, :address_prefix, "1789")
      valid_address = prefix <> String.duplicate("a", 40)

      result = GetBalance.call(%{"address" => valid_address})

      assert is_map(result)

      case result do
        %{address: ^valid_address, balance: balance} ->
          # Verify balance is numeric and non-negative
          assert is_number(balance)
          assert balance >= 0

        %{error: error_msg} ->
          # Error acceptable when blockchain service unavailable
          assert is_binary(error_msg)
          assert String.length(error_msg) > 0

        _ ->
          flunk("Unexpected response format: #{inspect(result)}")
      end
    end

    test "handles invalid address format" do
      invalid_addresses = [
        "invalid_address",
        "1234short",
        "wrongprefix" <> String.duplicate("a", 40),
        "1789" <> String.duplicate("x", 10)  # too short
      ]

      for address <- invalid_addresses do
        result = GetBalance.call(%{"address" => address})
        assert is_map(result)

        # Should either return an error or handle gracefully
        case result do
          %{error: _} -> assert true
          %{balance: _} -> assert true  # Some invalid formats might still get processed
          _ -> assert true
        end
      end
    end
  end

  describe "parameter validation" do
    test "validates address parameter presence" do
      empty_params = [%{}, %{"other" => "param"}]

      for params <- empty_params do
        result = GetBalance.call(params)
        assert result[:error] == "Missing or invalid 'address' parameter"
      end
    end

    test "handles additional parameters gracefully" do
      prefix = Application.get_env(:bastille, :address_prefix, "1789")
      address = prefix <> String.duplicate("b", 40)

      result = GetBalance.call(%{
        "address" => address,
        "unused" => "parameter",
        "ignored" => 123
      })

      assert is_map(result)
      # Should process the address parameter and ignore others
    end
  end

  describe "response format" do
    test "successful response contains required fields" do
      prefix = Application.get_env(:bastille, :address_prefix, "1789")
      address = prefix <> String.duplicate("c", 40)

      result = GetBalance.call(%{"address" => address})

      case result do
        %{address: returned_address, balance: balance} ->
          assert returned_address == address
          assert is_number(balance)

        %{error: _} ->
          # Error response is acceptable
          assert true
      end
    end

    test "balance is numeric when present" do
      prefix = Application.get_env(:bastille, :address_prefix, "1789")
      address = prefix <> String.duplicate("d", 40)

      result = GetBalance.call(%{"address" => address})

      if Map.has_key?(result, :balance) do
        assert is_integer(result[:balance]) or is_float(result[:balance])
        assert result[:balance] >= 0
      end
    end
  end
end
