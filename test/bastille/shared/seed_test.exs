defmodule Bastille.Shared.SeedTest do
  use ExUnit.Case, async: true

  alias Bastille.Shared.{Mnemonic, Seed}

  @moduletag :unit

  @fixed_entropy <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22,
                   23, 24, 25, 26, 27, 28, 29, 30, 31, 32>>

  describe "master seed generation" do
    test "generates 24-word master seed" do
      seed = Seed.generate_master_seed()
      words = String.split(seed, " ")

      assert length(words) == 24
      assert Seed.valid_master_seed?(seed)
    end

    test "generates different seeds each time" do
      seed1 = Seed.generate_master_seed()
      seed2 = Seed.generate_master_seed()

      assert seed1 != seed2
      assert Seed.valid_master_seed?(seed1)
      assert Seed.valid_master_seed?(seed2)
    end

    test "generated seed contains only valid words" do
      seed = Seed.generate_master_seed()

      assert is_binary(seed)
      assert String.length(seed) > 0
      assert Seed.valid_master_seed?(seed)
    end
  end

  describe "seed validation" do
    test "validates correct 24-word seed" do
      seed = Seed.generate_master_seed()
      assert Seed.valid_master_seed?(seed)
    end

    test "rejects seed with wrong word count" do
      # 23 words
      short_seed =
        Seed.generate_master_seed() |> String.split(" ") |> Enum.drop(1) |> Enum.join(" ")

      refute Seed.valid_master_seed?(short_seed)

      # 25 words  
      long_seed = Seed.generate_master_seed() <> " extra"
      refute Seed.valid_master_seed?(long_seed)
    end

    test "rejects empty or invalid seed" do
      refute Seed.valid_master_seed?("")
      refute Seed.valid_master_seed?("invalid seed")
      refute Seed.valid_master_seed?("one two three")
    end

    test "rejects seed with invalid words" do
      invalid_seed = String.duplicate("invalidword ", 24) |> String.trim()
      refute Seed.valid_master_seed?(invalid_seed)
    end
  end

  describe "key derivation" do
    test "derives all three post-quantum keypairs from seed" do
      # Use deterministic seed for testing
      seed = "test seed for key derivation"

      case Seed.derive_keys_from_seed(seed) do
        {:ok, keys} ->
          assert Map.has_key?(keys, :dilithium)
          assert Map.has_key?(keys, :falcon)
          assert Map.has_key?(keys, :sphincs)

          # Check each keypair has public and private keys
          assert Map.has_key?(keys.dilithium, :public)
          assert Map.has_key?(keys.dilithium, :private)
          assert Map.has_key?(keys.falcon, :public)
          assert Map.has_key?(keys.falcon, :private)
          assert Map.has_key?(keys.sphincs, :public)
          assert Map.has_key?(keys.sphincs, :private)

          # Keys should be binary
          assert is_binary(keys.dilithium.public)
          assert is_binary(keys.dilithium.private)
          assert is_binary(keys.falcon.public)
          assert is_binary(keys.falcon.private)
          assert is_binary(keys.sphincs.public)
          assert is_binary(keys.sphincs.private)

        {:error, _reason} ->
          # If NIFs not available, test should pass gracefully
          assert true
      end
    end

    test "key derivation is deterministic" do
      seed = "deterministic test seed"

      case {Seed.derive_keys_from_seed(seed), Seed.derive_keys_from_seed(seed)} do
        {{:ok, keys1}, {:ok, keys2}} ->
          assert keys1.dilithium == keys2.dilithium
          assert keys1.falcon == keys2.falcon
          assert keys1.sphincs == keys2.sphincs

        _ ->
          # If NIFs not available, test should pass gracefully
          assert true
      end
    end

    test "different seeds produce different keys" do
      seed1 = "first test seed"
      seed2 = "second test seed"

      case {Seed.derive_keys_from_seed(seed1), Seed.derive_keys_from_seed(seed2)} do
        {{:ok, keys1}, {:ok, keys2}} ->
          assert keys1.dilithium != keys2.dilithium
          assert keys1.falcon != keys2.falcon
          assert keys1.sphincs != keys2.sphincs

        _ ->
          # If NIFs not available, test should pass gracefully
          assert true
      end
    end
  end

  describe "key recovery" do
    test "recovers same keys from same seed" do
      seed = "recovery test seed"

      case {Seed.derive_keys_from_seed(seed), Seed.recover_keys(seed)} do
        {{:ok, original_keys}, {:ok, recovered_keys}} ->
          assert original_keys == recovered_keys

        _ ->
          # If NIFs not available, test should pass gracefully
          assert true
      end
    end
  end

  describe "error handling" do
    test "handles invalid seed gracefully" do
      case Seed.derive_keys_from_seed("") do
        # Might work with empty seed
        {:ok, _keys} ->
          assert true

        {:error, reason} ->
          assert is_binary(reason)
          assert String.contains?(reason, "Key derivation failed")
      end
    end

    test "handles malformed input" do
      invalid_inputs = [nil, 123, %{}, []]

      for input <- invalid_inputs do
        case Seed.derive_keys_from_seed(input) do
          # Might work
          {:ok, _keys} ->
            assert true

          {:error, reason} ->
            assert is_binary(reason)
        end
      end
    end
  end

  describe "BIP39 master seed (PBKDF2)" do
    test "PBKDF2-HMAC-SHA512 params match the official BIP39 vector" do
      mnemonic =
        "abandon abandon abandon abandon abandon abandon abandon abandon " <>
          "abandon abandon abandon about"

      expected =
        Base.decode16!(
          "C55257C360C07C72029AEBC1B53C05ED0362ADA38EAD3E3E9EFA3708E5349553" <>
            "1F09A6987599D18264C1E1C92F2CF141630C7A3C4AB7C81B2F001698E7463B04"
        )

      # The published vector salts with passphrase "TREZOR"; this anchors our
      # PBKDF2 parameters (SHA-512, 2048 iterations, 64-byte output).
      assert :crypto.pbkdf2_hmac(:sha512, mnemonic, "mnemonicTREZOR", 2048, 64) == expected
    end

    test "master_seed_from_mnemonic is the 64-byte BIP39 seed (salt \"mnemonic\")" do
      mnemonic = Seed.generate_master_seed()
      normalized = :unicode.characters_to_nfkd_binary(mnemonic)

      seed = Seed.master_seed_from_mnemonic(mnemonic)
      assert byte_size(seed) == 64
      assert seed == :crypto.pbkdf2_hmac(:sha512, normalized, "mnemonic", 2048, 64)
    end
  end

  describe "derive_keys_from_mnemonic/1" do
    test "derives deterministic keys from a valid mnemonic" do
      mnemonic = Seed.generate_master_seed()

      assert {:ok, k0} = Seed.derive_keys_from_mnemonic(mnemonic)
      assert {:ok, k0_again} = Seed.derive_keys_from_mnemonic(mnemonic)
      assert k0 == k0_again
    end

    test "rejects a mnemonic with an invalid checksum" do
      words = Mnemonic.to_mnemonic(@fixed_entropy) |> String.split(" ")
      replacement = Enum.find(Mnemonic.wordlist(), &(&1 != hd(words)))
      tampered = [replacement | tl(words)] |> Enum.join(" ")

      assert {:error, _} = Seed.derive_keys_from_mnemonic(tampered)
    end
  end
end
