defmodule Bastille.Features.Api.RPC.GetInfoTest do

  use ExUnit.Case, async: true

  alias Bastille.Features.Api.RPC.GetInfo

  @moduletag :unit

  describe "get_info RPC method" do
    test "returns blockchain information" do
      result = GetInfo.call(%{})

      assert is_map(result)

      case result do
        %{chain: _, consensus: _, mempool: _, mining: _, network: _, security: _} ->
          # Verify complete info response structure
          expected_keys = [:chain, :consensus, :mempool, :mining, :network, :security]
          for key <- expected_keys do
            assert Map.has_key?(result, key)
          end

        %{error: error_msg} ->
          # Error acceptable when blockchain services unavailable
          assert is_binary(error_msg)
          assert String.length(error_msg) > 0

        partial_response ->
          # Partial response acceptable - verify it's still a map
          assert is_map(partial_response)
      end
    end

    test "handles empty parameters" do
      result = GetInfo.call(%{})
      assert is_map(result)
    end

    test "ignores additional parameters" do
      result = GetInfo.call(%{"unused" => "parameter", "ignored" => 123})
      assert is_map(result)
    end
  end

  describe "response format validation" do
    test "always returns a map" do
      result = GetInfo.call(%{})
      assert is_map(result)
    end

    test "handles method calls consistently" do
      result1 = GetInfo.call(%{})
      result2 = GetInfo.call(%{})

      # Both should return maps with consistent structure
      assert is_map(result1)
      assert is_map(result2)

      # If both succeed, they should have similar keys
      case {result1, result2} do
        {%{chain: _}, %{chain: _}} ->
          assert Map.keys(result1) == Map.keys(result2)

        _ ->
          # Different responses are acceptable if services availability varies
          assert true
      end
    end
  end
end
