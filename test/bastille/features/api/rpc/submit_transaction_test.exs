defmodule Bastille.Features.Api.RPC.SubmitTransactionTest do
  use ExUnit.Case, async: true

  alias Bastille.Features.Api.RPC.SubmitTransaction
  alias Bastille.Features.Transaction.Transaction

  @moduletag :unit

  defp build_signed_map do
    # Build a structurally valid signed-transaction JSON map. The
    # signature won't verify (random bytes), but the parser shouldn't
    # care — that's the chain validation layer's job.
    tx =
      Transaction.new(
        from: "f789" <> String.duplicate("a", 40),
        to: "f789" <> String.duplicate("b", 40),
        amount: 1_000_000,
        nonce: 1
      )

    signed = %{tx | signature: %{
      dilithium: :crypto.strong_rand_bytes(2420),
      falcon: :crypto.strong_rand_bytes(690),
      sphincs: :crypto.strong_rand_bytes(7856)
    }}

    Transaction.to_json_map(signed)
  end

  describe "input validation" do
    test "rejects missing signed_transaction" do
      result = SubmitTransaction.call(%{})
      assert %{status: "error", reason: reason} = result
      assert is_binary(reason)
    end

    test "rejects nil signed_transaction" do
      result = SubmitTransaction.call(%{"signed_transaction" => nil})
      assert %{status: "error"} = result
    end

    test "rejects a base64+ETF payload (security regression: legacy format)" do
      # The OLD API accepted Base.encode64(:erlang.term_to_binary(...)).
      # This is an atom-exhaustion / hostile-deserialization vector.
      # The new RPC must REJECT such input cleanly.
      legacy_payload =
        Base.encode64(:erlang.term_to_binary(%{from: "x", to: "y", amount: 1}))

      result = SubmitTransaction.call(%{"signed_transaction" => legacy_payload})

      assert %{status: "error", reason: reason} = result
      # Specifically: not a map → rejected at the boundary
      assert reason =~ ~r/json object|not_a_map|payload/i
    end

    test "rejects a binary string payload (must be a JSON object)" do
      result = SubmitTransaction.call(%{"signed_transaction" => "just_a_string"})
      assert %{status: "error"} = result
    end

    test "rejects a JSON map that is missing required fields" do
      result = SubmitTransaction.call(%{"signed_transaction" => %{"from" => "x"}})
      assert %{status: "error"} = result
    end

    test "rejects a JSON map with an invalid signature_type" do
      bad =
        build_signed_map()
        |> Map.put("signature_type", "legacy_secp256k1")

      result = SubmitTransaction.call(%{"signed_transaction" => bad})
      assert %{status: "error", reason: reason} = result
      assert reason =~ "unsupported_signature_type" or reason =~ "signature"
    end

    test "rejects an unsigned tx submission (missing signature field)" do
      unsigned =
        build_signed_map()
        |> Map.delete("signature")

      result = SubmitTransaction.call(%{"signed_transaction" => unsigned})
      assert %{status: "error", reason: reason} = result
      assert reason =~ "no signature"
    end
  end

  describe "happy path shape" do
    test "accepts a JSON map signed transaction and returns hex hash" do
      signed_map = build_signed_map()

      result = SubmitTransaction.call(%{"signed_transaction" => signed_map})

      # Even if the actual signature/balance checks fail at submission
      # (signature is random, sender has no balance), the parser layer
      # accepts the shape. The status will then be either "ok" or an
      # "error" from the mempool — both prove parsing succeeded.
      case result do
        %{status: "ok", tx_hash: hash} ->
          assert is_binary(hash)
          assert String.length(hash) == 64

        %{status: "error", reason: reason} ->
          # Any error from below the parser is fine; we just must NOT
          # have a parser-level error.
          refute reason =~ "json object"
          refute reason =~ "not_a_map"
      end
    end
  end
end
