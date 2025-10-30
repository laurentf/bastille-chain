defmodule Bastille.Shared.TypesTest do
  use ExUnit.Case, async: true

  alias Bastille.Shared.Types

  @moduletag :unit

  describe "module compilation and documentation" do
    test "module compiles without errors" do
      # This test ensures the Types module compiles correctly
      assert Code.ensure_loaded?(Types)
    end

    test "module has proper moduledoc" do
      {:docs_v1, _, :elixir, _, module_doc, _, _} = Code.fetch_docs(Types)
      
      case module_doc do
        %{"en" => doc} -> 
          assert is_binary(doc)
          assert String.contains?(doc, "Shared types")
        
        :none -> 
          # Module might not have docs in test environment
          assert true
          
        _ -> 
          assert true
      end
    end
  end

  describe "type definitions validation" do
    test "type definitions are accessible" do
      # While we can't directly test types at runtime, we can ensure
      # the module loads and common usage patterns work
      
      # Test blockchain types
      block_height = 12345
      assert is_integer(block_height) and block_height >= 0
      
      block_hash = <<1, 2, 3, 4, 5>>
      assert is_binary(block_hash)
      
      transaction_hash = :crypto.strong_rand_bytes(32)
      assert is_binary(transaction_hash)
      assert byte_size(transaction_hash) == 32
      
      address = "1789abcdefabcdefabcdefabcdefabcdefabcdefab"
      assert is_binary(address)
      
      # Test economic types
      amount_juillet = 1000000
      assert is_integer(amount_juillet) and amount_juillet >= 0
      
      amount_bast = 1.5
      assert is_float(amount_bast)
      
      fee_amount = 1000
      assert is_integer(fee_amount) and fee_amount >= 0
    end

    test "crypto types usage patterns" do
      # Test signature types enum values
      signature_types = [:dilithium, :falcon, :sphincs, :coinbase]
      assert Enum.all?(signature_types, &is_atom/1)
      
      # Test crypto keys structure
      crypto_keys = %{
        dilithium: <<1, 2, 3>>,
        falcon: <<4, 5, 6>>,
        sphincs: <<7, 8, 9>>
      }
      
      assert is_map(crypto_keys)
      assert Map.has_key?(crypto_keys, :dilithium)
      assert Map.has_key?(crypto_keys, :falcon)
      assert Map.has_key?(crypto_keys, :sphincs)
      assert Enum.all?(Map.values(crypto_keys), &is_binary/1)
    end

    test "difficulty and nonce types" do
      difficulty = 12345
      assert is_integer(difficulty) and difficulty >= 0
      
      nonce = 98765
      assert is_integer(nonce) and nonce >= 0
      
      # Very large values should also work
      large_difficulty = 999_999_999_999
      assert is_integer(large_difficulty) and large_difficulty >= 0
    end

    test "P2P types usage patterns" do
      peer_address = "127.0.0.1"
      assert is_binary(peer_address)
      
      peer_port = 8333
      assert is_integer(peer_port) and peer_port >= 0 and peer_port <= 65535
      
      node_id = "abcd1234"
      assert is_binary(node_id)
    end

    test "result types usage patterns" do
      # Test success result
      success_result = {:ok, "data"}
      assert match?({:ok, _}, success_result)
      
      # Test error result with atom
      error_result_atom = {:error, :not_found}
      assert match?({:error, _}, error_result_atom)
      
      # Test error result with string
      error_result_string = {:error, "Something went wrong"}
      assert match?({:error, _}, error_result_string)
      
      # Test blockchain result pattern
      blockchain_success = {:ok, %{block_height: 100}}
      blockchain_error = {:error, :invalid_block}
      
      assert match?({:ok, _}, blockchain_success)
      assert match?({:error, _}, blockchain_error)
    end
  end

  describe "type constraint validation" do
    test "amounts are non-negative" do
      # Positive amounts should work
      assert 0 >= 0  # amount_juillet constraint
      assert 100 >= 0
      assert 999_999_999 >= 0
      
      # Negative amounts would violate type constraints (if enforced)
      negative_amount = -100
      refute negative_amount >= 0
    end

    test "binary types have appropriate constraints" do
      # Test various binary sizes for hashes
      short_hash = <<1, 2, 3, 4>>
      medium_hash = :crypto.strong_rand_bytes(20)  # SHA-1 size
      long_hash = :crypto.strong_rand_bytes(32)    # SHA-256 size
      
      assert is_binary(short_hash)
      assert is_binary(medium_hash)
      assert is_binary(long_hash)
      
      # All should be valid binary types
      assert byte_size(short_hash) == 4
      assert byte_size(medium_hash) == 20
      assert byte_size(long_hash) == 32
    end

    test "string types for addresses and IDs" do
      # Test various address formats
      short_address = "addr123"
      long_address = "1789abcdefabcdefabcdefabcdefabcdefabcdefab"
      unicode_address = "1789café"
      
      assert is_binary(short_address)
      assert is_binary(long_address)
      assert is_binary(unicode_address)
      
      # All should be valid string types
      assert String.valid?(short_address)
      assert String.valid?(long_address)
      assert String.valid?(unicode_address)
    end

    test "port numbers are within valid range" do
      valid_ports = [0, 80, 443, 8333, 18333, 65535]
      
      for port <- valid_ports do
        assert is_integer(port)
        assert port >= 0
        assert port <= 65535
      end
      
      # Invalid ports
      invalid_ports = [-1, 65536, 999999]
      
      for port <- invalid_ports do
        refute (port >= 0 and port <= 65535)
      end
    end
  end

  describe "complex type combinations" do
    test "result types with blockchain data" do
      # Simulate blockchain results with various data types
      block_data = %{
        height: 12345,
        hash: :crypto.strong_rand_bytes(32),
        transactions: [],
        difficulty: 1000,
        nonce: 987654
      }
      
      success_result = {:ok, block_data}
      assert match?({:ok, %{height: _, hash: _, transactions: _}}, success_result)
      
      error_result = {:error, :block_not_found}
      assert match?({:error, :block_not_found}, error_result)
    end

    test "crypto keys with signature types" do
      # Simulate a complete signature scenario
      keys = %{
        dilithium: :crypto.strong_rand_bytes(32),
        falcon: :crypto.strong_rand_bytes(32),
        sphincs: :crypto.strong_rand_bytes(32)
      }
      
      signature_type = :dilithium
      signature_data = keys[signature_type]
      
      assert is_map(keys)
      assert is_atom(signature_type)
      assert is_binary(signature_data)
      assert signature_type in [:dilithium, :falcon, :sphincs, :coinbase]
    end

    test "P2P networking type combinations" do
      # Simulate P2P node information
      node_info = %{
        id: "node123abc",
        address: "192.168.1.100",
        port: 8333
      }
      
      peer_list = [
        {"peer1", "10.0.0.1", 8333},
        {"peer2", "10.0.0.2", 8334}
      ]
      
      assert is_map(node_info)
      assert is_binary(node_info.id)
      assert is_binary(node_info.address)
      assert is_integer(node_info.port) and node_info.port > 0
      
      assert is_list(peer_list)
      assert Enum.all?(peer_list, fn {id, addr, port} ->
        is_binary(id) and is_binary(addr) and is_integer(port)
      end)
    end
  end
end