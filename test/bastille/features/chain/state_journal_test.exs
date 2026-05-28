defmodule Bastille.Features.Chain.StateJournalTest do
  use ExUnit.Case, async: false

  alias Bastille.Infrastructure.Storage.CubDB.State

  @moduletag :unit

  defp uniq_addr, do: "f789" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)

  test "rollback_block restores balances and nonces, then drops the journal" do
    a = uniq_addr()
    b = uniq_addr()

    # State "after block 2".
    State.update_balance(a, 100)
    State.update_nonce(a, 5)
    State.update_balance(b, 50)
    State.update_nonce(b, 0)

    # Journal the pre-"block 3" state, then apply "block 3" changes.
    block3 = :crypto.strong_rand_bytes(32)
    :ok = State.store_journal(block3, [{a, 100, 5}, {b, 50, 0}])
    State.update_balance(a, 70)
    State.update_nonce(a, 6)
    State.update_balance(b, 80)

    # Rolling back "block 3" returns to the exact "after block 2" state.
    assert :ok = State.rollback_block(block3)
    assert {:ok, 100} = State.get_balance(a)
    assert {:ok, 5} = State.get_nonce(a)
    assert {:ok, 50} = State.get_balance(b)
    assert {:ok, 0} = State.get_nonce(b)

    # The journal is consumed.
    assert {:error, :no_journal} = State.rollback_block(block3)
  end

  test "delete_journal drops a journal without touching state" do
    a = uniq_addr()
    State.update_balance(a, 42)

    block = :crypto.strong_rand_bytes(32)
    :ok = State.store_journal(block, [{a, 999, 9}])

    assert :ok = State.delete_journal(block)
    assert {:error, :no_journal} = State.rollback_block(block)
    assert {:ok, 42} = State.get_balance(a)
  end
end
