defmodule Bastille.Features.Api.RPC.ExtractKeysForSigning do
  @moduledoc """
  ⚠️  TEST HELPER - Extract private keys from mnemonic for sign_transaction payload

  Takes a mnemonic and returns:
  - The derived address
  - The 3 private keys formatted for sign_transaction RPC

  DEV/TEST ONLY - Never use in production!
  """

  def call(params) do
    if Mix.env() != :prod do
      handle_key_extraction(params)
    else
      %{"error" => %{"code" => -32_601, "message" => "extract_keys_for_signing not available in production"}}
    end
  end

  defp handle_key_extraction(%{"mnemonic" => mnemonic}) do
    mnemonic_str = if is_list(mnemonic), do: Enum.join(mnemonic, " "), else: mnemonic

    case Bastille.derive_keys_from_seed(mnemonic_str) do
      {:ok, result} ->
        %{
          "result" => %{
            "message" => "⚠️  DEV/TEST ONLY - Private keys for sign_transaction payload",
            "address" => result.address,
            "sign_transaction_payload" => %{
              "dilithium_key" => result.keys.dilithium.private_key,
              "falcon_key" => result.keys.falcon.private_key,
              "sphincs_key" => result.keys.sphincs.private_key
            },
            "usage_example" => %{
              "step_1" => "Create unsigned transaction with this address",
              "step_2" => "Use sign_transaction_payload private keys to sign (3 keys only)",
              "step_3" => "Submit signed transaction"
            }
          }
        }
      {:error, message} ->
        %{"error" => %{"code" => -32_602, "message" => "Key extraction failed: #{message}"}}
    end
  rescue
    error -> %{"error" => %{"code" => -32_602, "message" => "Extract keys failed: #{Exception.message(error)}"}}
  end

  defp handle_key_extraction(_params) do
    %{
      "error" => %{
        "code" => -32_602,
        "message" => "Missing required parameter. Provide 'mnemonic' (string or word array)"
      }
    }
  end
end
