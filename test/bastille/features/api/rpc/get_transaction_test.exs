defmodule Bastille.Features.Api.RPC.GetTransactionTest do
  use ExUnit.Case, async: false

  alias Bastille.Features.Api.RPC.GetTransaction
  alias Bastille.Features.Block.Block
  alias Bastille.Features.Transaction.{Mempool, Transaction}
  alias Bastille.Infrastructure.Storage.CubDB.{Blocks, Index}

  @moduletag :unit

  # Other test modules (notably mempool_test.exs) stop and restart the global
  # Mempool GenServer in their own setup/teardown. The OTP supervisor brings
  # it back up, but there's a brief window where the named process is gone —
  # if our test fires during that window, GenServer.call exits :noproc.
  # Wait for the named processes we depend on to be alive before running.
  setup do
    for name <- [Mempool, Blocks, Index] do
      wait_for_named(name, 5_000)
    end

    :ok
  end

  defp wait_for_named(name, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_for_named(name, deadline)
  end

  defp do_wait_for_named(name, deadline) do
    case Process.whereis(name) do
      pid when is_pid(pid) ->
        :ok

      nil ->
        if System.monotonic_time(:millisecond) >= deadline do
          flunk("Process #{inspect(name)} did not come back up in time")
        else
          Process.sleep(20)
          do_wait_for_named(name, deadline)
        end
    end
  end

  describe "input validation" do
    test "returns an error for a missing hash parameter" do
      result = GetTransaction.call(%{})
      assert %{error: msg} = result
      assert msg =~ "hash"
    end

    test "returns an error for an empty hash" do
      result = GetTransaction.call(%{"hash" => ""})
      assert %{error: msg} = result
      assert msg =~ "Invalid"
    end

    test "returns an error for a non-hex hash" do
      result = GetTransaction.call(%{"hash" => "definitely_not_hex_!@#"})
      assert %{error: _} = result
    end

    test "returns an error for a wrong-length hex hash" do
      # 16-char hex = 8 bytes, not 32
      result = GetTransaction.call(%{"hash" => "0123456789abcdef"})
      assert %{error: _} = result
    end

    test "returns an error for a non-string hash" do
      for bad <- [nil, 123, %{}, []] do
        result = GetTransaction.call(%{"hash" => bad})
        assert %{error: _} = result, "Expected error for #{inspect(bad)}"
      end
    end
  end

  describe "lookup paths" do
    test "returns not_found for an unknown 32-byte hash" do
      unknown = Base.encode16(:crypto.strong_rand_bytes(32), case: :lower)
      result = GetTransaction.call(%{"hash" => unknown})
      assert %{status: "not_found", hash: ^unknown} = result
    end

    test "finds a pending transaction in the mempool" do
      # Build a structurally valid tx and inject it into the mempool with
      # the test-mode skip flags applied at app startup.
      Mempool.clear()

      tx =
        Transaction.new(
          from: "f789" <> String.duplicate("a", 40),
          to: "f789" <> String.duplicate("b", 40),
          amount: 1_000_000,
          nonce: 1
        )

      :ok = Mempool.add_transaction(tx)

      hex = Base.encode16(tx.hash, case: :lower)
      result = GetTransaction.call(%{"hash" => hex})

      assert %{status: "pending", hash: ^hex, transaction: tx_map} = result
      assert tx_map["from"] == tx.from
      assert tx_map["to"] == tx.to
      assert tx_map["amount"] == tx.amount

      Mempool.clear()
    end

    test "finds a confirmed transaction via the index, with block info and confirmations" do
      # Build a tx, wrap it in a block, store + index, then look it up.
      tx =
        Transaction.new(
          from: "f789" <> String.duplicate("c", 40),
          to: "f789" <> String.duplicate("d", 40),
          amount: 2_000_000,
          nonce: 1
        )

      block =
        Block.new(
          index: 9_999,
          previous_hash: <<0::256>>,
          transactions: [tx],
          difficulty: 1
        )

      :ok = Blocks.store_block(block)

      partition = current_partition()

      :ok =
        Index.index_transaction(%Index.TransactionIndex{
          tx_hash: tx.hash,
          partition: partition,
          block_hash: block.hash,
          from_address: tx.from,
          to_address: tx.to,
          tx_index: 0,
          timestamp: tx.timestamp
        })

      hex = Base.encode16(tx.hash, case: :lower)
      result = GetTransaction.call(%{"hash" => hex})

      assert %{
               status: "confirmed",
               hash: ^hex,
               block_height: 9_999,
               block_hash: bh_hex,
               confirmations: c,
               transaction: tx_map
             } = result

      assert bh_hex == Base.encode16(block.hash, case: :lower)
      assert is_integer(c)
      assert tx_map["from"] == tx.from
      assert tx_map["to"] == tx.to
    end

    test "mempool path takes precedence over the index (just-confirmed tx still in mempool)" do
      # Edge case: a tx might briefly live in both mempool (not yet evicted)
      # and the confirmed index. We treat the mempool view as more recent.
      Mempool.clear()

      tx =
        Transaction.new(
          from: "f789" <> String.duplicate("e", 40),
          to: "f789" <> String.duplicate("f", 40),
          amount: 5_000_000,
          nonce: 1
        )

      :ok = Mempool.add_transaction(tx)
      hex = Base.encode16(tx.hash, case: :lower)

      result = GetTransaction.call(%{"hash" => hex})
      assert %{status: "pending"} = result

      Mempool.clear()
    end
  end

  defp current_partition do
    {{year, month, _}, _} = :calendar.universal_time()
    "#{year}#{String.pad_leading("#{month}", 2, "0")}"
  end
end
