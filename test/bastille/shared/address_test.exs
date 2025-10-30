defmodule Bastille.Features.Shared.AddressFeatureTest do
  use ExUnit.Case, async: true

  alias Bastille.Shared.Crypto

  @moduletag :unit

  test "generated address has correct prefix and length" do
    kp = Crypto.generate_pq_keypair()
    address = Crypto.generate_bastille_address(kp)
    prefix = Application.get_env(:bastille, :address_prefix, "1789")
    assert String.starts_with?(address, prefix)
    assert String.length(address) == String.length(prefix) + 40
    assert Crypto.valid_address?(address)
  end
end
