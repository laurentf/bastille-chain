defmodule Bastille.Features.Api.RPC.SignTransaction do
  @moduledoc """
  Production-safe transaction signing with post-quantum 2/3 threshold.

  SECURITY: Only accepts pre-derived private keys + unsigned transaction.
  Public keys are retrieved from storage (stored during address generation).

  Clean workflow:
  1. extract_keys_for_signing (dev/test) → private keys only
  2. create_unsigned_transaction → unsigned transaction
  3. sign_transaction → signed transaction (gets public keys from storage)
  """

  alias Bastille.Shared.Crypto
  alias Bastille.Features.Transaction.Transaction

  # Pattern matching on function heads instead of case
  def call(%{"dilithium_key" => _dil_key, "falcon_key" => _fal_key, "sphincs_key" => _sph_key,
             "unsigned_transaction" => _unsigned_tx} = params) do
    handle_secure_signing(params)
  end

  def call(_invalid_params) do
    %{"error" => %{"code" => -32_602, "message" => "Invalid parameters. Provide: unsigned_transaction + 3 private keys (dilithium_key, falcon_key, sphincs_key). Public keys retrieved from storage."}}
  end

  # === PRODUCTION SIGNING ===

  defp handle_secure_signing(%{"dilithium_key" => dil_key_b64, "falcon_key" => fal_key_b64, "sphincs_key" => sph_key_b64,
                               "unsigned_transaction" => unsigned_tx_b64}) do
    try do
      # Decode keys
      {:ok, dil_key} = Base.decode64(dil_key_b64)
      {:ok, fal_key} = Base.decode64(fal_key_b64)
      {:ok, sph_key} = Base.decode64(sph_key_b64)

      # Decode unsigned transaction
      {:ok, tx_binary} = Base.decode64(unsigned_tx_b64)
      unsigned_tx = :erlang.binary_to_term(tx_binary)

      # Validate private key sizes
      if valid_private_key_sizes?(dil_key, fal_key, sph_key) do
        # Retrieve public keys from storage
        case Crypto.get_public_keys_for_address(unsigned_tx.from) do
          {:ok, public_keys} ->
            # Create keypair structure
            keypair = %{
              dilithium: %{private: dil_key, public: public_keys.dilithium},
              falcon: %{private: fal_key, public: public_keys.falcon},
              sphincs: %{private: sph_key, public: public_keys.sphincs}
            }

            # Verify ownership by checking if the private keys match the stored public keys
            derived_address = Crypto.generate_bastille_address(keypair)

            if derived_address == unsigned_tx.from do
              signed_tx = Transaction.sign(unsigned_tx, keypair)
              format_signed_transaction(signed_tx)
            else
              %{"error" => %{"code" => -32_602, "message" => "Private keys do not match transaction sender address"}}
            end

          {:error, :not_found} ->
            %{"error" => %{"code" => -32_602, "message" => "Public keys not found for address. Address must be generated through this node first."}}
        end
      else
        %{"error" => %{"code" => -32_602, "message" => "Invalid private key sizes"}}
      end
    rescue
      error -> %{"error" => %{"code" => -32_602, "message" => "Signing failed: #{Exception.message(error)}"}}
    end
  end

  # === HELPERS ===

  defp valid_private_key_sizes?(dil_key, fal_key, sph_key) do
    byte_size(dil_key) == Crypto.dilithium_private_key_size() and
    byte_size(fal_key) == Crypto.falcon_private_key_size() and
    byte_size(sph_key) == Crypto.sphincs_private_key_size()
  end

  defp format_signed_transaction(signed_tx) do
    %{
      "result" => %{
        "signed_transaction" => Base.encode64(:erlang.term_to_binary(signed_tx)),
        "transaction_hash" => Base.encode16(signed_tx.hash, case: :lower)
      }
    }
  end
end
