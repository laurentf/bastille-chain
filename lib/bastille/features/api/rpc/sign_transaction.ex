defmodule Bastille.Features.Api.RPC.SignTransaction do
  @moduledoc """
  Production-safe transaction signing with post-quantum 2/3 threshold.

  Accepts an `unsigned_transaction` JSON map (NOT base64-encoded ETF) and
  the 3 base64-encoded private keys. The unsigned map is the same shape
  produced by `create_unsigned_transaction`.

  Public keys are retrieved from local storage (they were stored when the
  address was generated on this node). The signer's ownership is verified
  by re-deriving the address from `(private_key, stored_public_key)` and
  comparing against `unsigned_tx.from`.

  ## Why JSON map and not ETF base64
  `:erlang.binary_to_term/1` on attacker-controlled bytes is a sharp
  knife: it can flood the atom table or instantiate unexpected term
  shapes. The RPC boundary must never accept ETF. See
  `Transaction.from_json_map/1` for the strict, fail-closed parser.
  """

  require Logger

  alias Bastille.Shared.Crypto
  alias Bastille.Features.Transaction.Transaction

  def call(
        %{
          "dilithium_key" => _,
          "falcon_key" => _,
          "sphincs_key" => _,
          "unsigned_transaction" => _
        } = params
      ) do
    handle_secure_signing(params)
  end

  def call(_invalid_params) do
    rpc_error(
      -32_602,
      "Invalid parameters. Provide: unsigned_transaction (JSON map) + 3 base64 private keys (dilithium_key, falcon_key, sphincs_key)."
    )
  end

  defp handle_secure_signing(%{
         "dilithium_key" => dil_b64,
         "falcon_key" => fal_b64,
         "sphincs_key" => sph_b64,
         "unsigned_transaction" => unsigned_payload
       }) do
    with {:ok, dil_key} <- decode_b64(dil_b64, "dilithium_key"),
         {:ok, fal_key} <- decode_b64(fal_b64, "falcon_key"),
         {:ok, sph_key} <- decode_b64(sph_b64, "sphincs_key"),
         :ok <- check_key_sizes(dil_key, fal_key, sph_key),
         {:ok, unsigned_map} <- coerce_unsigned_map(unsigned_payload),
         {:ok, unsigned_tx} <- Transaction.from_json_map(unsigned_map),
         {:ok, public_keys} <- Crypto.get_public_keys_for_address(unsigned_tx.from),
         keypair <- build_keypair(dil_key, fal_key, sph_key, public_keys),
         :ok <- verify_ownership(keypair, unsigned_tx.from) do
      # Embed the sender's public keys so any node can verify the signature
      # without having seen this address before (they bind to `from`).
      signed_tx = %{Transaction.sign(unsigned_tx, keypair) | public_keys: public_keys}

      Logger.info("✍️ Tx signed for #{unsigned_tx.from}")

      Logger.info(
        "   └─ hash: #{Base.encode16(signed_tx.hash, case: :lower) |> String.slice(0, 16)}..."
      )

      # Flat: the RPC dispatcher already wraps the return value under `result:`.
      %{
        "signed_transaction" => Transaction.to_json_map(signed_tx),
        "transaction_hash" => Base.encode16(signed_tx.hash, case: :lower)
      }
    else
      {:error, {:invalid_base64, field}} ->
        rpc_error(-32_602, "Invalid base64 for #{field}")

      {:error, :invalid_key_sizes} ->
        rpc_error(-32_602, "Invalid private key sizes")

      {:error, :unsigned_not_a_map} ->
        rpc_error(-32_602, "unsigned_transaction must be a JSON object")

      {:error, :not_found} ->
        rpc_error(
          -32_602,
          "Public keys not found for sender address. The address must be generated on this node first."
        )

      {:error, :ownership_mismatch} ->
        rpc_error(-32_602, "Private keys do not match the transaction sender address")

      {:error, reason} ->
        rpc_error(-32_602, "Signing failed: #{inspect(reason)}")
    end
  rescue
    error -> rpc_error(-32_602, "Signing failed: #{Exception.message(error)}")
  end

  defp decode_b64(v, field) when is_binary(v) do
    case Base.decode64(v) do
      {:ok, bytes} -> {:ok, bytes}
      :error -> {:error, {:invalid_base64, field}}
    end
  end

  defp decode_b64(_, field), do: {:error, {:invalid_base64, field}}

  defp check_key_sizes(dil, fal, sph) do
    if byte_size(dil) == Crypto.dilithium_private_key_size() and
         byte_size(fal) == Crypto.falcon_private_key_size() and
         byte_size(sph) == Crypto.sphincs_private_key_size() do
      :ok
    else
      {:error, :invalid_key_sizes}
    end
  end

  # The unsigned_transaction payload should arrive as a JSON object (=
  # plain Elixir map after Jason decoding). Reject anything else explicitly
  # — we never call binary_to_term here.
  defp coerce_unsigned_map(payload) when is_map(payload), do: {:ok, payload}
  defp coerce_unsigned_map(_), do: {:error, :unsigned_not_a_map}

  defp build_keypair(dil_priv, fal_priv, sph_priv, public_keys) do
    %{
      dilithium: %{private: dil_priv, public: public_keys.dilithium},
      falcon: %{private: fal_priv, public: public_keys.falcon},
      sphincs: %{private: sph_priv, public: public_keys.sphincs}
    }
  end

  # Two-step ownership proof:
  # 1. The stored public keys derive an address equal to the claimed sender.
  #    (Always true if the address was originally generated on this node.)
  # 2. The supplied private keys actually correspond to those public keys —
  #    proven by signing a test message and verifying with the public keys.
  #    Without step 2, anyone could submit arbitrary private keys for a
  #    known sender and the check would silently pass.
  defp verify_ownership(keypair, claimed_from) do
    derived = Crypto.generate_bastille_address(keypair)

    if derived != claimed_from do
      {:error, :ownership_mismatch}
    else
      test_message = "bastille-ownership-proof-" <> claimed_from
      signature = Crypto.sign(test_message, keypair)

      pubs = %{
        dilithium: keypair.dilithium.public,
        falcon: keypair.falcon.public,
        sphincs: keypair.sphincs.public
      }

      if Crypto.verify(test_message, signature, pubs) do
        :ok
      else
        {:error, :ownership_mismatch}
      end
    end
  end

  defp rpc_error(code, message) do
    %{"error" => %{"code" => code, "message" => message}}
  end
end
