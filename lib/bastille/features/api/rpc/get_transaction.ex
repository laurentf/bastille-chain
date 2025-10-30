defmodule Bastille.Features.Api.RPC.GetTransaction do
  @moduledoc """
  Handles the get_transaction RPC command.
  Returns transaction details for a given hash.
  """

  def call(%{"hash" => hash}) do
    tx = Bastille.get_transaction(hash)
    %{hash: hash, transaction: tx}
  rescue
    error -> %{error: Exception.message(error)}
  end
end
