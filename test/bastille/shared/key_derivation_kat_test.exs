defmodule Bastille.Shared.KeyDerivationKATTest do
  use ExUnit.Case, async: true

  alias Bastille.Shared.{Crypto, Mnemonic, Seed}

  @moduletag :unit

  # Frozen reference vectors: entropy -> mnemonic -> keypairs + address.
  # If a dependency bump or a derivation change alters any output, these fail
  # loudly — the mnemonic->address contract must never silently change.
  @vectors Path.join(:code.priv_dir(:bastille), "test/kat_keys.json")
           |> File.read!()
           |> Jason.decode!()
           |> Map.fetch!("vectors")

  test "KAT file is populated" do
    assert length(@vectors) >= 8
  end

  for vector <- @vectors do
    @vector vector
    test "vector #{String.slice(vector["entropy"], 0, 12)}… reproduces frozen keys + address" do
      v = @vector
      mnemonic = v["entropy"] |> Base.decode16!(case: :lower) |> Mnemonic.to_mnemonic()

      assert {:ok, keys} = Seed.derive_keys_from_mnemonic(mnemonic)

      assert Base.encode16(keys.dilithium.public, case: :lower) == v["dilithium_pub"]
      assert Base.encode16(keys.falcon.public, case: :lower) == v["falcon_pub"]
      assert Base.encode16(keys.sphincs.public, case: :lower) == v["sphincs_pub"]

      address =
        Crypto.generate_bastille_address(%{
          dilithium: keys.dilithium,
          falcon: keys.falcon,
          sphincs: keys.sphincs
        })

      assert address == v["address"]
    end
  end
end
