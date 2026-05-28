defmodule Bastille.Features.Keys.MnemonicRecoveryTest do
  use ExUnit.Case, async: true

  alias Bastille.Shared.{Crypto, Seed}

  @moduletag :unit

  # End-to-end recovery contract: a mnemonic re-derived from scratch (as a fresh
  # node would on restore) yields the identical wallet, and those recovered keys
  # actually sign. Cross-process determinism is covered separately (KAT +
  # the keygen POC); derivation is pure/stateless, so no node restart is needed.

  defp recover(mnemonic) do
    {:ok, keys} = Seed.derive_keys_from_mnemonic(mnemonic)

    address =
      Crypto.generate_bastille_address(%{
        dilithium: keys.dilithium,
        falcon: keys.falcon,
        sphincs: keys.sphincs
      })

    {keys, address}
  end

  test "the same mnemonic recovers an identical wallet (address + all keys)" do
    mnemonic = Seed.generate_master_seed()

    {keys_a, addr_a} = recover(mnemonic)
    {keys_b, addr_b} = recover(mnemonic)

    assert addr_a == addr_b
    assert keys_a.dilithium.public == keys_b.dilithium.public
    assert keys_a.falcon.public == keys_b.falcon.public
    assert keys_a.sphincs.public == keys_b.sphincs.public
    assert keys_a.dilithium.private == keys_b.dilithium.private
    assert keys_a.falcon.private == keys_b.falcon.private
    assert keys_a.sphincs.private == keys_b.sphincs.private
  end

  test "a different mnemonic recovers a different wallet" do
    {_, addr1} = recover(Seed.generate_master_seed())
    {_, addr2} = recover(Seed.generate_master_seed())

    assert addr1 != addr2
  end

  test "recovered keys sign a message that verifies under the 2/3 threshold" do
    {keys, _address} = recover(Seed.generate_master_seed())

    message = "transfer 1789 juillet to citoyen"
    signature = Crypto.sign(message, keys)

    public_keys = %{
      dilithium: keys.dilithium.public,
      falcon: keys.falcon.public,
      sphincs: keys.sphincs.public
    }

    assert Crypto.verify(message, signature, public_keys)
    refute Crypto.verify("tampered message", signature, public_keys)
  end
end
