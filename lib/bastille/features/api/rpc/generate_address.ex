defmodule Bastille.Features.Api.RPC.GenerateAddress do
  @moduledoc """
  Handles the generate_address RPC command.
  Generates a new mnemonic phrase and derives the corresponding address.
  """

  def call(_params) do
    # Use the Bastille facade for clean API
    result = Bastille.generate_address_with_mnemonic()

    %{
      address: result.address,
      mnemonic: result.mnemonic_list,
      mnemonic_phrase: result.mnemonic
    }
  rescue
    error -> %{error: Exception.message(error)}
  end
end
