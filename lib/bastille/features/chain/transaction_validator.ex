defmodule Bastille.Features.Chain.TransactionValidator do
  @moduledoc """
  Pure transaction validation against the on-disk State.

  Lives outside the `Chain` GenServer so callers — most notably the
  `Mempool` — don't have to do a `GenServer.call(Chain, …)` to check a
  transaction. That call was a real cascading-timeout risk: while `Chain`
  is busy in `handle_call({:add_block, …})`, any concurrent
  `validate_transaction` request would queue behind it and could exceed
  the default 5s deadline.

  This module reads `State` (its own GenServer, never blocked by Chain)
  and applies pure validation rules — balance, nonce, address format —
  with no Chain dependency.
  """

  require Logger

  alias Bastille.Features.Transaction.Transaction
  alias Bastille.Infrastructure.Storage.CubDB.State
  alias Bastille.Shared.Address

  @doc """
  Validate a transaction against the current on-chain account state.

  Coinbase and the synthetic `"1789Genesis"` sender bypass the balance/
  nonce/address checks — they are constructed internally and trusted by
  the consensus layer.

  Returns `:ok` or `{:error, reason}`. Possible reasons:
  - `{:insufficient_balance, required: N, available: M}`
  - `{:invalid_nonce, expected: N, got: M}`
  - `{:invalid_address_format, address: …}`
  """
  @spec validate(Transaction.t()) :: :ok | {:error, term()}
  def validate(%Transaction{signature_type: :coinbase}), do: :ok
  def validate(%Transaction{from: "1789Genesis"}), do: :ok

  def validate(%Transaction{} = tx) do
    %{from: from, amount: amount, fee: fee, nonce: tx_nonce} = tx

    current_balance =
      case State.get_balance(from) do
        {:ok, balance} -> balance
        {:error, _} -> 0
      end

    current_nonce =
      case State.get_nonce(from) do
        {:ok, nonce} -> nonce
        {:error, :not_found} -> 0
        {:error, _} -> 0
      end

    total_cost = amount + fee

    with :ok <- validate_balance(current_balance, total_cost),
         :ok <- validate_nonce(tx_nonce, current_nonce + 1) do
      validate_address_format(from)
    end
  end

  defp validate_balance(current, required) when current >= required, do: :ok

  defp validate_balance(current, required),
    do: {:error, {:insufficient_balance, required: required, available: current}}

  defp validate_nonce(tx_nonce, expected) when tx_nonce == expected, do: :ok

  defp validate_nonce(tx_nonce, expected),
    do: {:error, {:invalid_nonce, expected: expected, got: tx_nonce}}

  # Same shape as Chain.validate_address_format/1 — kept here to avoid
  # crossing the Chain GenServer boundary.
  defp validate_address_format("1789Genesis"), do: :ok
  defp validate_address_format("legacy_" <> _), do: :ok

  defp validate_address_format(address) when is_binary(address) do
    case Address.valid?(address) do
      true -> :ok
      false -> {:error, {:invalid_address_format, address: address}}
    end
  end

  defp validate_address_format(address), do: {:error, {:invalid_address_format, address: address}}
end
