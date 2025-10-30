defmodule Bastille.Features.Api.RPC.SubmitTransaction do
  @moduledoc """
  Handles the submit_transaction RPC command.
  """

  def call(params) do
    signed_tx_b64 = params["signed_transaction"]
    {:ok, tx_binary} = Base.decode64(signed_tx_b64)
    tx = :erlang.binary_to_term(tx_binary)

    case Bastille.submit_transaction(tx) do
      :ok ->
        %{status: "ok", tx_hash: Base.encode16(tx.hash, case: :lower)}
      error ->
        %{status: "error", reason: inspect(error)}
    end
  rescue
    error -> %{status: "error", reason: Exception.message(error)}
  end
end
