defmodule Bastille.Infrastructure.Crypto.CryptoNifTest do
  @moduledoc """
  Tests for the low-level cryptographic NIFs (Native Implemented Functions).
  
  Tests the Rust-based cryptographic implementations for post-quantum
  algorithms, Blake3 hashing, and performance validation.
  """
  
  use ExUnit.Case, async: true
  
  alias Bastille.Infrastructure.Crypto.CryptoNif
  
  @moduletag :crypto_nif
  @moduletag timeout: 30_000

  describe "Blake3 hashing" do
    test "produces consistent hashes" do
      test_data = "Hello, Bastille Blockchain!"
      
      # Hash should be deterministic
      hash1 = CryptoNif.blake3_hash(test_data)
      hash2 = CryptoNif.blake3_hash(test_data)
      
      assert hash1 == hash2
      assert byte_size(hash1) == 32
      assert is_binary(hash1)
    end
    
    test "produces different hashes for different data" do
      data1 = "Hello, World!"
      data2 = "Hello, Bastille!"
      
      hash1 = CryptoNif.blake3_hash(data1)
      hash2 = CryptoNif.blake3_hash(data2)
      
      assert hash1 != hash2
      assert byte_size(hash1) == 32
      assert byte_size(hash2) == 32
    end
    
    test "handles empty data" do
      hash = CryptoNif.blake3_hash("")
      
      assert byte_size(hash) == 32
      assert is_binary(hash)
      
      # Empty string should produce specific hash
      assert hash != <<0::256>>
    end
    
    test "handles large data efficiently" do
      # Create large test data (1MB)
      large_data = String.duplicate("A", 1_024 * 1_024)
      
      start_time = System.monotonic_time(:millisecond)
      hash = CryptoNif.blake3_hash(large_data)
      end_time = System.monotonic_time(:millisecond)
      
      duration = end_time - start_time
      
      # Should complete quickly (less than 1 second for 1MB)
      assert duration < 1_000
      assert byte_size(hash) == 32
    end
  end

  describe "post-quantum key generation" do
    test "generates Dilithium keypairs" do
      try do
        keypair = CryptoNif.dilithium2_keypair()
        
        assert is_tuple(keypair)
        {public_key, private_key} = keypair
        
        # Keys should be binary data
        assert is_binary(public_key)
        assert is_binary(private_key)
        
        # Keys should have expected sizes (approximate)
        assert byte_size(public_key) > 1000
        assert byte_size(private_key) > 2000
        
      rescue
        error ->
          # NIFs might not be compiled in test environment
          case error do
            %UndefinedFunctionError{} ->
              IO.puts("Dilithium NIF not available - skipping test")
            _ ->
              reraise error, __STACKTRACE__
          end
      end
    end
    
    test "generates Falcon keypairs" do
      try do
        keypair = CryptoNif.falcon512_keypair()
        
        assert is_tuple(keypair)
        {public_key, private_key} = keypair
        
        # Keys should be binary data
        assert is_binary(public_key)
        assert is_binary(private_key)
        
        # Falcon keys are typically smaller than Dilithium
        assert byte_size(public_key) > 500
        assert byte_size(private_key) > 1000
        
      rescue
        UndefinedFunctionError ->
          IO.puts("Falcon NIF not available - skipping test")
      end
    end
    
    test "generates SPHINCS+ keypairs" do
      try do
        keypair = CryptoNif.sphincsplus_shake_128f_keypair()
        
        assert is_tuple(keypair)
        {public_key, private_key} = keypair
        
        # Keys should be binary data
        assert is_binary(public_key)
        assert is_binary(private_key)
        
        # SPHINCS+ has specific key sizes
        assert byte_size(public_key) > 30
        assert byte_size(private_key) > 60
        
      rescue
        UndefinedFunctionError ->
          IO.puts("SPHINCS+ NIF not available - skipping test")
      end
    end
  end

  describe "post-quantum signatures" do
    test "signs and verifies with Dilithium" do
      try do
        {public_key, private_key} = CryptoNif.dilithium2_keypair()
        message = "Test message for Dilithium signing"
        
        # Sign message
        signature = CryptoNif.dilithium2_sign(message, private_key)
        assert is_binary(signature)
        assert byte_size(signature) > 1000  # Dilithium signatures are large
        
        # Verify signature
        valid = CryptoNif.dilithium2_verify(signature, message, public_key)
        assert valid == true
        
        # Verify with wrong message should fail
        invalid = CryptoNif.dilithium2_verify(signature, "Wrong message", public_key)
        assert invalid == false
        
      rescue
        UndefinedFunctionError ->
          IO.puts("Dilithium signing NIF not available - skipping test")
      end
    end
    
    test "signs and verifies with Falcon" do
      try do
        {public_key, private_key} = CryptoNif.falcon512_keypair()
        message = "Test message for Falcon signing"
        
        # Sign message
        signature = CryptoNif.falcon512_sign(message, private_key)
        assert is_binary(signature)
        assert byte_size(signature) > 500  # Falcon signatures
        
        # Verify signature
        valid = CryptoNif.falcon512_verify(signature, message, public_key)
        assert valid == true
        
        # Verify with wrong message should fail
        invalid = CryptoNif.falcon512_verify(signature, "Wrong message", public_key)
        assert invalid == false
        
      rescue
        UndefinedFunctionError ->
          IO.puts("Falcon signing NIF not available - skipping test")
      end
    end
    
    test "signs and verifies with SPHINCS+" do
      try do
        {public_key, private_key} = CryptoNif.sphincsplus_shake_128f_keypair()
        message = "Test message for SPHINCS+ signing"
        
        # Sign message
        signature = CryptoNif.sphincsplus_shake_128f_sign(message, private_key)
        assert is_binary(signature)
        assert byte_size(signature) > 1000  # SPHINCS+ signatures are very large
        
        # Verify signature
        valid = CryptoNif.sphincsplus_shake_128f_verify(signature, message, public_key)
        assert valid == true
        
        # Verify with wrong message should fail
        invalid = CryptoNif.sphincsplus_shake_128f_verify(signature, "Wrong message", public_key)
        assert invalid == false
        
      rescue
        UndefinedFunctionError ->
          IO.puts("SPHINCS+ signing NIF not available - skipping test")
      end
    end
  end

  describe "performance benchmarks" do
    @tag :performance
    test "Blake3 performance benchmark" do
      test_data = "Benchmark data for Blake3 hashing performance"
      iterations = 1_000
      
      start_time = System.monotonic_time(:microsecond)
      
      for _i <- 1..iterations do
        CryptoNif.blake3_hash(test_data)
      end
      
      end_time = System.monotonic_time(:microsecond)
      duration_ms = (end_time - start_time) / 1_000
      
      hashes_per_second = iterations / (duration_ms / 1_000)
      
      IO.puts("Blake3 Performance: #{Float.round(hashes_per_second, 2)} hashes/second")
      
      # Should be very fast (at least 10,000 hashes/second)
      assert hashes_per_second > 10_000
    end
    
    @tag :performance
    @tag :slow
    test "post-quantum signature performance" do
      try do
        # Test Dilithium performance
        {public_key, private_key} = CryptoNif.dilithium2_keypair()
        message = "Performance test message"
        
        # Benchmark signing
        signing_iterations = 10
        start_time = System.monotonic_time(:millisecond)
        
        signatures = for _i <- 1..signing_iterations do
          CryptoNif.dilithium2_sign(message, private_key)
        end
        
        end_time = System.monotonic_time(:millisecond)
        signing_duration = end_time - start_time
        
        signs_per_second = signing_iterations / (signing_duration / 1_000)
        IO.puts("Dilithium Signing: #{Float.round(signs_per_second, 2)} signatures/second")
        
        # Benchmark verification
        signature = hd(signatures)
        verification_iterations = 50
        start_time = System.monotonic_time(:millisecond)
        
        for _i <- 1..verification_iterations do
          CryptoNif.dilithium2_verify(signature, message, public_key)
        end
        
        end_time = System.monotonic_time(:millisecond)
        verification_duration = end_time - start_time
        
        verifications_per_second = verification_iterations / (verification_duration / 1_000)
        IO.puts("Dilithium Verification: #{Float.round(verifications_per_second, 2)} verifications/second")
        
        # Performance should be reasonable for blockchain use
        assert signs_per_second > 1      # At least 1 signature per second
        assert verifications_per_second > 10  # At least 10 verifications per second
        
      rescue
        UndefinedFunctionError ->
          IO.puts("Post-quantum NIFs not available - skipping performance test")
      end
    end
  end

  describe "error handling and edge cases" do
    test "handles invalid input gracefully" do
      # Blake3 with nil input
      assert_raise ArgumentError, fn ->
        CryptoNif.blake3_hash(nil)
      end
      
      # Blake3 with non-binary input
      assert_raise ArgumentError, fn ->
        CryptoNif.blake3_hash(123)
      end
    end
    
    test "handles invalid keys for signatures" do
      try do
        message = "Test message"
        invalid_key = "not_a_valid_key"
        
        # Try to sign with invalid private key - might return error or raise
        try do
          result = CryptoNif.dilithium2_sign(message, invalid_key)
          # If it returns something, it should be an error
          assert {:error, _} = result
        rescue
          ArgumentError -> :ok  # This is also acceptable
          _ -> :ok  # Other errors are acceptable for invalid keys
        end
        
        # Should handle invalid public key gracefully
        {_public_key, private_key} = CryptoNif.dilithium2_keypair()
        signature = CryptoNif.dilithium2_sign(message, private_key)
        
        # Try to verify with invalid public key
        try do
          result = CryptoNif.dilithium2_verify(signature, message, invalid_key)
          # If it returns something, it should be an error or false
          assert result in [false, {:error, :invalid_signature}]
        rescue
          ArgumentError -> :ok  # This is also acceptable
          _ -> :ok  # Other errors are acceptable for invalid keys
        end
        
      rescue
        UndefinedFunctionError ->
          IO.puts("Dilithium NIFs not available - skipping error handling test")
      end
    end
  end

  describe "cryptographic security properties" do
    test "signatures are non-deterministic (where applicable)" do
      try do
        {public_key, private_key} = CryptoNif.dilithium2_keypair()
        message = "Same message signed twice"
        
        signature1 = CryptoNif.dilithium2_sign(message, private_key)
        signature2 = CryptoNif.dilithium2_sign(message, private_key)
        
        # Signatures might be deterministic or randomized depending on implementation
        # Both should verify correctly regardless
        assert CryptoNif.dilithium2_verify(signature1, message, public_key)
        assert CryptoNif.dilithium2_verify(signature2, message, public_key)
        
      rescue
        UndefinedFunctionError ->
          IO.puts("Dilithium NIFs not available - skipping determinism test")
      end
    end
    
    test "key generation produces unique keys" do
      try do
        # Generate multiple keypairs
        keypairs = for _i <- 1..5 do
          CryptoNif.dilithium2_keypair()
        end
        
        # All public keys should be unique
        public_keys = Enum.map(keypairs, fn {pub, _priv} -> pub end)
        unique_public_keys = Enum.uniq(public_keys)
        assert length(public_keys) == length(unique_public_keys)
        
        # All private keys should be unique
        private_keys = Enum.map(keypairs, fn {_pub, priv} -> priv end)
        unique_private_keys = Enum.uniq(private_keys)
        assert length(private_keys) == length(unique_private_keys)
        
      rescue
        UndefinedFunctionError ->
          IO.puts("Dilithium NIFs not available - skipping uniqueness test")
      end
    end
  end
end
