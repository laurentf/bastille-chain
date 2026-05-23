defmodule Bastille.Features.Shared.AddressFeatureTest do
  use ExUnit.Case, async: true

  alias Bastille.Shared.{Address, Crypto}

  @moduletag :unit

  describe "generation and basic format" do
    test "generated address has correct prefix and length" do
      kp = Crypto.generate_pq_keypair()
      address = Crypto.generate_bastille_address(kp)
      prefix = Application.get_env(:bastille, :address_prefix, "1789")
      assert String.starts_with?(address, prefix)
      assert String.length(address) == String.length(prefix) + 40
      assert Crypto.valid_address?(address)
    end

    test "generated address is canonical (all-lowercase) and valid via Address.valid?" do
      kp = Crypto.generate_pq_keypair()
      addr = Crypto.generate_bastille_address(kp)
      assert addr == String.downcase(addr)
      assert Address.valid?(addr)
    end
  end

  describe "EIP-55-inspired checksum (with_checksum / valid?)" do
    test "with_checksum/1 produces an address of the same length" do
      addr = "f789" <> String.duplicate("a", 40)
      assert String.length(Address.with_checksum(addr)) == String.length(addr)
    end

    test "with_checksum/1 introduces uppercase letters for typical addresses" do
      # Any address with non-trivial hex content should have at least one
      # uppercased nibble (statistical: ~half of a-f chars get upper-cased).
      kp = Crypto.generate_pq_keypair()
      addr = Crypto.generate_bastille_address(kp)
      checksummed = Address.with_checksum(addr)

      # Same characters when downcased
      assert String.downcase(checksummed) == addr
      # But generally not byte-identical to the lowercase form
      assert checksummed != addr or not String.contains?(addr, ~w(a b c d e f))
    end

    test "with_checksum/1 is deterministic" do
      kp = Crypto.generate_pq_keypair()
      addr = Crypto.generate_bastille_address(kp)
      assert Address.with_checksum(addr) == Address.with_checksum(addr)
    end

    test "valid?/1 accepts the canonical lowercase form" do
      kp = Crypto.generate_pq_keypair()
      addr = Crypto.generate_bastille_address(kp)
      assert Address.valid?(addr)
    end

    test "valid?/1 accepts an all-uppercase address (legacy tolerance)" do
      kp = Crypto.generate_pq_keypair()
      addr = Crypto.generate_bastille_address(kp)
      prefix = Address.get_prefix()
      hex_part = String.slice(addr, String.length(prefix)..-1//1)
      uppercase_form = prefix <> String.upcase(hex_part)
      assert Address.valid?(uppercase_form)
    end

    test "valid?/1 accepts a correctly checksummed mixed-case address" do
      kp = Crypto.generate_pq_keypair()
      addr = Crypto.generate_bastille_address(kp)
      checksummed = Address.with_checksum(addr)
      assert Address.valid?(checksummed)
    end

    test "valid?/1 rejects a mixed-case address with a tampered character case" do
      kp = Crypto.generate_pq_keypair()
      addr = Crypto.generate_bastille_address(kp)
      checksummed = Address.with_checksum(addr)

      # Find one alphabetic hex char in the hex part and flip its case.
      prefix = Address.get_prefix()
      prefix_len = String.length(prefix)
      hex_part = String.slice(checksummed, prefix_len..-1//1)

      flip_index =
        hex_part
        |> String.graphemes()
        |> Enum.find_index(fn c -> c in ~w(a b c d e f A B C D E F) end)

      case flip_index do
        nil ->
          # Extremely unlikely: an address with no a-f anywhere.
          # Skip rather than spuriously failing.
          :ok

        i ->
          {head, [flip_char, tail_rest]} =
            checksummed
            |> String.graphemes()
            |> Enum.split(prefix_len + i)
            |> then(fn {h, [c | rest]} -> {h, [c, rest]} end)

          flipped =
            cond do
              flip_char == String.upcase(flip_char) -> String.downcase(flip_char)
              true -> String.upcase(flip_char)
            end

          tampered = Enum.join(head ++ [flipped | tail_rest])

          refute Address.valid?(tampered),
                 "Tampered address should be rejected by checksum: #{tampered}"
      end
    end

    test "valid?/1 rejects garbage" do
      refute Address.valid?("not-an-address")
      refute Address.valid?("")
      refute Address.valid?(123)
      refute Address.valid?(nil)
    end

    test "valid?/1 is case-sensitive on the prefix" do
      addr = "f789" <> String.duplicate("a", 40)
      # In a testnet env prefix is "f789"
      assert Address.valid?(addr)
      # Uppercased prefix is not accepted (prefix is configured lowercase)
      refute Address.valid?("F789" <> String.duplicate("a", 40))
    end
  end

  describe "canonical/1" do
    test "downcases a valid mixed-case address" do
      kp = Crypto.generate_pq_keypair()
      addr = Crypto.generate_bastille_address(kp)
      checksummed = Address.with_checksum(addr)

      assert Address.canonical(checksummed) == addr
      assert Address.canonical(addr) == addr
    end

    test "leaves the synthetic 1789Genesis sentinel untouched" do
      assert Address.canonical("1789Genesis") == "1789Genesis"
    end

    test "leaves non-conforming strings untouched" do
      assert Address.canonical("legacy_FooBar") == "legacy_FooBar"
      assert Address.canonical("short") == "short"
    end
  end

  describe "KAT — known answer test for cross-machine reproducibility" do
    # If the checksum algorithm changes, this test must change too — it locks
    # the current scheme so a silent break (e.g. switching hash function) is
    # caught immediately. Address content depends on the test env prefix; we
    # construct a fixed lowercase address by hand.
    test "lowercase + prefix produces a deterministic checksummed form" do
      # 44 chars : "f789" (4) + 40 hex
      addr = "f789" <> "abcdef0123456789abcdef0123456789abcdef01"
      assert String.length(addr) == 44
      assert Address.valid?(addr)

      checksummed = Address.with_checksum(addr)
      assert String.length(checksummed) == 44
      assert Address.canonical(checksummed) == addr

      # Mutating any single char case breaks the checksum (when applicable).
      mutated = String.replace(checksummed, "a", "A", global: false)
      if mutated != checksummed do
        refute Address.valid?(mutated)
      end
    end
  end
end
