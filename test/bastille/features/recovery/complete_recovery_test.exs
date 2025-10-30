defmodule Bastille.Features.Keys.CompleteRecoveryFeatureTest do
  use ExUnit.Case, async: true

  alias Bastille.Shared.{Seed, Mnemonic, Crypto}

  @moduletag :unit

  describe "24-word master seed complete recovery" do
    test "generate 24 French words and derive all PQ keys" do
      seed = Seed.generate_master_seed()
      assert is_binary(seed)

      words = String.split(seed, " ")
      assert length(words) == 24
      assert Mnemonic.valid_mnemonic?(seed)

      {:ok, keys} = Seed.derive_keys_from_seed(seed)
      assert is_map(keys)
      assert Map.has_key?(keys, :dilithium)
      assert Map.has_key?(keys, :falcon)
      assert Map.has_key?(keys, :sphincs)
    end

    test "deterministic: same seed => same keys" do
      seed = Seed.generate_master_seed()

      {:ok, k1} = Seed.derive_keys_from_seed(seed)
      {:ok, k2} = Seed.derive_keys_from_seed(seed)

      assert k1.dilithium == k2.dilithium
      assert k1.falcon == k2.falcon
      assert k1.sphincs == k2.sphincs
    end

    test "address generation stable from derived keys" do
      seed = Seed.generate_master_seed()
      {:ok, keys} = Seed.derive_keys_from_seed(seed)

      address1 = Crypto.generate_bastille_address(%{
        dilithium: keys.dilithium,
        falcon: keys.falcon,
        sphincs: keys.sphincs
      })

      address2 = Crypto.generate_bastille_address(%{
        dilithium: keys.dilithium,
        falcon: keys.falcon,
        sphincs: keys.sphincs
      })

      assert is_binary(address1)
      assert String.starts_with?(address1, Application.get_env(:bastille, :address_prefix, "1789"))
      assert address1 == address2
    end
  end
end
