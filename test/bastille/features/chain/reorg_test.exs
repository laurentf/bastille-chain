defmodule Bastille.Features.Chain.ReorgTest do
  @moduledoc """
  Sprint 4.4 — transactional rollback + reapply.

  Drives `Chain.reorganize/1` directly with a `ReorgSearch`-shaped result so we
  test the chain *switch* in isolation from the P2P common-ancestor search
  (covered by Sprint 4.3). Blocks are real: mined coinbase blocks that pass full
  validation (PoW, merkle root, consensus) against the ultra-easy test target.

  `mix` runs a live, mining node and these GenServers are global singletons, so
  rather than fight the supervisor we pause background mining (for a stable tip)
  and build each scenario *relative to the current chain head*, paying fresh
  random addresses so balances are deterministic regardless of chain history.
  """

  use ExUnit.Case, async: false

  alias Bastille.Features.Chain.Chain
  alias Bastille.Features.Block.Block
  alias Bastille.Features.Mining.Mining
  alias Bastille.Features.Transaction.Transaction
  alias Bastille.Features.Tokenomics.Token

  @moduletag :integration

  # Same value as config/test.exs — the consensus engine and our miner must
  # agree on the target or mined blocks would fail consensus.
  @max_target 0x00FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF

  setup do
    # Fresh genesis + paused mining, via the supervisor (no singleton churn).
    Bastille.TestHelper.reset_chain_storage()

    tip = Chain.get_head_block()

    %{
      tip: tip,
      miner_a: uniq_addr(),
      miner_b: uniq_addr(),
      reward: Token.block_reward(tip.header.index + 1)
    }
  end

  test "switches onto a heavier fork: rolls back the old tip, applies the fork", %{
    tip: tip,
    miner_a: miner_a,
    miner_b: miner_b,
    reward: reward
  } do
    # Our main chain extends the live tip with one block paid to miner A.
    a1 = mine_coinbase(tip.header.index + 1, tip.hash, miner_a)
    assert :ok = Chain.add_block(a1)
    assert Chain.get_balance(miner_a) == reward
    new_height = Chain.get_height()

    # Competing fork off the same tip: two blocks paid to miner B — heavier.
    b1 = mine_coinbase(tip.header.index + 1, tip.hash, miner_b)
    b2 = mine_coinbase(tip.header.index + 2, b1.hash, miner_b)

    result = reorg_result(tip.hash, [b1, b2], better?: true)
    assert {:ok, summary} = Chain.reorganize(result)

    assert summary.rolled_back == 1
    assert summary.applied == 2
    assert summary.new_height == new_height + 1

    # Chain now follows the fork.
    assert Chain.get_height() == new_height + 1
    assert Chain.get_head_block().hash == b2.hash

    # Old tip's coinbase reverted; the fork's two coinbases credited.
    assert Chain.get_balance(miner_a) == 0
    assert Chain.get_balance(miner_b) == 2 * reward
  end

  test "aborts all-or-nothing when a fork block fails to validate", %{
    tip: tip,
    miner_a: miner_a,
    miner_b: miner_b,
    reward: reward
  } do
    a1 = mine_coinbase(tip.header.index + 1, tip.hash, miner_a)
    assert :ok = Chain.add_block(a1)
    assert Chain.get_balance(miner_a) == reward
    height = Chain.get_height()

    # Fork: B1 is valid, B2 is corrupted (hash no longer matches its contents).
    b1 = mine_coinbase(tip.header.index + 1, tip.hash, miner_b)
    b2_valid = mine_coinbase(tip.header.index + 2, b1.hash, miner_b)
    b2_bad = %{b2_valid | hash: :crypto.strong_rand_bytes(32)}

    result = reorg_result(tip.hash, [b1, b2_bad], better?: true)
    assert {:error, :invalid_hash} = Chain.reorganize(result)

    # Original chain fully restored — as if the reorg never happened.
    assert Chain.get_height() == height
    assert Chain.get_head_block().hash == a1.hash
    assert Chain.get_balance(miner_a) == reward
    assert Chain.get_balance(miner_b) == 0
  end

  test "refuses a fork that is not heavier", %{tip: tip, miner_a: miner_a, miner_b: miner_b} do
    a1 = mine_coinbase(tip.header.index + 1, tip.hash, miner_a)
    assert :ok = Chain.add_block(a1)
    height = Chain.get_height()

    b1 = mine_coinbase(tip.header.index + 1, tip.hash, miner_b)
    result = reorg_result(tip.hash, [b1], better?: false)

    assert {:error, :not_better} = Chain.reorganize(result)
    assert Chain.get_height() == height
    assert Chain.get_head_block().hash == a1.hash
  end

  test "abandons the reorg when the ancestor is outside the in-memory window", %{
    tip: tip,
    miner_a: miner_a,
    miner_b: miner_b
  } do
    a1 = mine_coinbase(tip.header.index + 1, tip.hash, miner_a)
    assert :ok = Chain.add_block(a1)
    height = Chain.get_height()

    unknown_ancestor = :crypto.strong_rand_bytes(32)
    fork_block = mine_coinbase(tip.header.index + 1, unknown_ancestor, miner_b)
    result = reorg_result(unknown_ancestor, [fork_block], better?: true)

    assert {:error, :ancestor_not_in_memory} = Chain.reorganize(result)
    assert Chain.get_height() == height
    assert Chain.get_head_block().hash == a1.hash
  end

  # ── Sprint 4.5 — edge cases ──────────────────────────────────────────────

  test "cascaded double reorg: B replaces A, then a heavier C replaces B", %{
    tip: tip,
    miner_a: miner_a,
    miner_b: miner_b,
    reward: reward
  } do
    miner_c = uniq_addr()
    h0 = tip.header.index

    # Main chain: one block to A.
    a1 = mine_coinbase(h0 + 1, tip.hash, miner_a)
    assert :ok = Chain.add_block(a1)

    # Reorg #1 — fork B (two blocks) off the tip replaces A.
    b1 = mine_coinbase(h0 + 1, tip.hash, miner_b)
    b2 = mine_coinbase(h0 + 2, b1.hash, miner_b)
    assert {:ok, _} = Chain.reorganize(reorg_result(tip.hash, [b1, b2], better?: true))
    assert Chain.get_head_block().hash == b2.hash
    assert Chain.get_balance(miner_a) == 0
    assert Chain.get_balance(miner_b) == 2 * reward

    # Reorg #2 — fork C (three blocks) off the same tip replaces B.
    c1 = mine_coinbase(h0 + 1, tip.hash, miner_c)
    c2 = mine_coinbase(h0 + 2, c1.hash, miner_c)
    c3 = mine_coinbase(h0 + 3, c2.hash, miner_c)
    assert {:ok, summary} = Chain.reorganize(reorg_result(tip.hash, [c1, c2, c3], better?: true))

    assert summary.rolled_back == 2
    assert summary.applied == 3
    assert Chain.get_head_block().hash == c3.hash
    assert Chain.get_height() == h0 + 3
    # B fully reverted, A still reverted, only C credited.
    assert Chain.get_balance(miner_b) == 0
    assert Chain.get_balance(miner_a) == 0
    assert Chain.get_balance(miner_c) == 3 * reward
  end

  test "reorg racing a freshly-mined block leaves a consistent chain", %{
    tip: tip,
    miner_a: miner_a,
    miner_b: miner_b,
    reward: reward
  } do
    h0 = tip.header.index

    a1 = mine_coinbase(h0 + 1, tip.hash, miner_a)
    assert :ok = Chain.add_block(a1)

    # "The block we were mining" extends the main chain, and arrives at the same
    # moment a heavier fork (B) is being adopted. add_block and reorganize are
    # both Chain GenServer calls, so they can't interleave — whichever wins, the
    # final chain must be the heavier fork B (a2 is either rolled back or rejected
    # as wrong-height), never a torn mix.
    a2 = mine_coinbase(h0 + 2, a1.hash, miner_a)
    b1 = mine_coinbase(h0 + 1, tip.hash, miner_b)
    b2 = mine_coinbase(h0 + 2, b1.hash, miner_b)

    add = Task.async(fn -> Chain.add_block(a2) end)

    reorg =
      Task.async(fn -> Chain.reorganize(reorg_result(tip.hash, [b1, b2], better?: true)) end)

    Task.await(add)
    Task.await(reorg)

    # Deterministic regardless of which call landed first.
    assert Chain.get_head_block().hash == b2.hash
    assert Chain.get_height() == h0 + 2
    assert Chain.get_balance(miner_a) == 0
    assert Chain.get_balance(miner_b) == 2 * reward
  end

  # ── helpers ────────────────────────────────────────────────────────────────

  defp uniq_addr, do: "f789" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)

  defp mine_coinbase(index, previous_hash, miner) do
    coinbase = Transaction.coinbase(miner, index)

    Block.new(
      index: index,
      previous_hash: previous_hash,
      transactions: [coinbase],
      difficulty: 1,
      timestamp: System.system_time(:second) + index
    )
    |> mine()
  end

  # Grind the nonce until the Blake3 block hash meets the configured target,
  # then stamp the canonical hash so the block passes Block.valid_hash?/1.
  defp mine(%Block{} = block) do
    target = div(@max_target, block.header.difficulty)
    nonce = grind(block, <<target::256>>, 0)
    %{block | header: %{block.header | nonce: nonce}} |> Block.calculate_blake3_hash()
  end

  defp grind(block, target_bin, nonce) do
    candidate = %{block | header: %{block.header | nonce: nonce}}

    if Mining.calculate_block_hash(candidate) <= target_bin do
      nonce
    else
      grind(block, target_bin, nonce + 1)
    end
  end

  defp reorg_result(ancestor_hash, fork_chain, opts) do
    %{
      ancestor_hash: ancestor_hash,
      fork_chain: fork_chain,
      alt_work: 0,
      local_work: 0,
      depth: length(fork_chain),
      better?: Keyword.fetch!(opts, :better?)
    }
  end
end
