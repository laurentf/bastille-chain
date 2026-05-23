defmodule Bastille.Features.Api.RPC.SubmitTransaction do
  @moduledoc """
  Submits a signed transaction to the mempool and broadcasts it to peers.

  Accepts the signed transaction as a JSON map (the shape returned by
  `sign_transaction`). NEVER accepts `:erlang.binary_to_term/1` input —
  the RPC boundary uses strict JSON parsing via
  `Transaction.from_json_map/1`.
  """

  require Logger

  alias Bastille.Features.Transaction.Transaction

  def call(%{"signed_transaction" => payload}) do
    with {:ok, map} <- coerce_map(payload),
         {:ok, tx} <- Transaction.from_json_map(map),
         :ok <- require_signature(tx),
         :ok <- Bastille.submit_transaction(tx) do
      Logger.info("📤 Tx submitted to mempool")
      Logger.info("   └─ hash: #{Base.encode16(tx.hash, case: :lower) |> String.slice(0, 16)}...")
      Logger.info("   └─ from: #{tx.from} → to: #{tx.to}")

      %{status: "ok", tx_hash: Base.encode16(tx.hash, case: :lower)}
    else
      {:error, :missing_signature} ->
        %{status: "error", reason: "Transaction has no signature"}

      {:error, :payload_not_a_map} ->
        %{status: "error", reason: "signed_transaction must be a JSON object"}

      {:error, reason} ->
        %{status: "error", reason: inspect(reason)}
    end
  rescue
    error -> %{status: "error", reason: Exception.message(error)}
  end

  def call(_), do: %{status: "error", reason: "Missing signed_transaction parameter"}

  defp coerce_map(m) when is_map(m), do: {:ok, m}
  defp coerce_map(_), do: {:error, :payload_not_a_map}

  defp require_signature(%Transaction{signature: nil}), do: {:error, :missing_signature}
  defp require_signature(_tx), do: :ok
end
