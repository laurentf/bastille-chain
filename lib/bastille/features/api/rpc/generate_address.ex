defmodule Bastille.Features.Api.RPC.GenerateAddress do
  @moduledoc """
  Handles the generate_address RPC command.

  Generates a new 24-word French mnemonic, derives the post-quantum keypair
  set, and returns the resulting address in both forms:

  - `address` : canonical, all-lowercase. This is the form stored on-chain
    and the one to use for internal comparisons.
  - `address_display` : EIP-55-inspired mixed-case form. Wallets and UIs
    should show this to users so copy/paste typos are detectable via the
    embedded checksum.

  The two forms are interchangeable on input — any RPC endpoint that
  accepts an address accepts either form (or all-uppercase legacy form),
  and canonicalizes to lowercase internally.
  """

  alias Bastille.Shared.Address

  def call(_params) do
    result = Bastille.generate_address_with_mnemonic()

    %{
      address: result.address,
      address_display: Address.with_checksum(result.address),
      mnemonic: result.mnemonic_list,
      mnemonic_phrase: result.mnemonic
    }
  rescue
    error -> %{error: Exception.message(error)}
  end
end
