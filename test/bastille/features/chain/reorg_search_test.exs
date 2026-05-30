defmodule Bastille.Features.Chain.ReorgSearchTest do
  use ExUnit.Case, async: true

  alias Bastille.Features.Block.Block
  alias Bastille.Features.Chain.ReorgSearch
  alias Bastille.Features.Mining.Mining

  @moduletag :unit

  # Minimal synthetic block — ReorgSearch only reads hash, previous_hash, difficulty.
  defp blk(hash, parent, difficulty) do
    %Block{
      hash: hash,
      transactions: [],
      header: %{
        index: 0,
        previous_hash: parent,
        timestamp: 0,
        merkle_root: <<0::256>>,
        nonce: 0,
        difficulty: difficulty,
        consensus_data: %{}
      }
    }
  end

  defp w(difficulty), do: Mining.work_for_difficulty(difficulty)

  describe "start/2" do
    test "requests the orphan's parent and seeds the accumulator with its own work" do
      orphan = blk("tip", "p1", 1)

      assert {:request, "p1", search} = ReorgSearch.start(orphan, local_work: 100)
      assert search.tip_hash == "tip"
      assert search.awaiting == "p1"
      assert search.depth == 0
      assert search.acc_work == w(1)
      assert search.fork_chain == [orphan]
      assert search.local_work == 100
    end
  end

  describe "advance/3 — reaching the common ancestor" do
    test "alternative chain with more total work wins (better? true)" do
      ancestor_work = 1_000_000
      # Local chain = ancestor + one diff-1 block.
      local_work = ancestor_work + w(1)

      orphan = blk("tip", "p1", 1)
      parent1 = blk("p1", "anc", 1)

      {:request, "p1", s1} = ReorgSearch.start(orphan, local_work: local_work)

      # parent1's parent ("anc") is a block we already know → ancestor_work given.
      assert {:found, result} = ReorgSearch.advance(s1, parent1, ancestor_work)
      assert result.ancestor_hash == "anc"
      assert result.depth == 1
      assert result.fork_chain == [parent1, orphan]
      assert result.alt_work == ancestor_work + w(1) + w(1)
      assert result.local_work == local_work
      assert result.better? == true
    end

    test "alternative chain with less total work loses (better? false)" do
      ancestor_work = 1_000_000
      # Local chain has more work past the ancestor than the two-block fork.
      local_work = ancestor_work + 3 * w(1)

      orphan = blk("tip", "p1", 1)
      parent1 = blk("p1", "anc", 1)

      {:request, "p1", s1} = ReorgSearch.start(orphan, local_work: local_work)

      assert {:found, result} = ReorgSearch.advance(s1, parent1, ancestor_work)
      assert result.alt_work == ancestor_work + 2 * w(1)
      assert result.better? == false
    end

    test "walks several hops before finding the ancestor, keeping fork_chain oldest-first" do
      orphan = blk("tip", "p1", 1)
      parent1 = blk("p1", "p2", 1)
      parent2 = blk("p2", "anc", 1)

      {:request, "p1", s1} = ReorgSearch.start(orphan, local_work: 0)
      # p1's parent ("p2") still unknown → keep walking.
      {:request, "p2", s2} = ReorgSearch.advance(s1, parent1, nil)
      assert s2.awaiting == "p2"
      assert s2.depth == 1

      # p2's parent ("anc") is known → done.
      assert {:found, result} = ReorgSearch.advance(s2, parent2, 500)
      assert result.depth == 2
      assert result.fork_chain == [parent2, parent1, orphan]
      assert result.alt_work == 500 + 3 * w(1)
    end
  end

  describe "advance/3 — guards" do
    test "aborts once the fork is deeper than max_depth" do
      orphan = blk("tip", "p1", 1)
      parent1 = blk("p1", "p2", 1)
      parent2 = blk("p2", "p3", 1)

      {:request, "p1", s1} = ReorgSearch.start(orphan, local_work: 0, max_depth: 2)
      {:request, "p2", s2} = ReorgSearch.advance(s1, parent1, nil)

      assert {:abort, :max_depth_exceeded, _} = ReorgSearch.advance(s2, parent2, nil)
    end

    test "ignores a block we were not waiting for" do
      orphan = blk("tip", "p1", 1)
      {:request, "p1", s1} = ReorgSearch.start(orphan, local_work: 0)

      stray = blk("somethingelse", "whatever", 1)
      assert {:ignore, ^s1} = ReorgSearch.advance(s1, stray, 123)
    end
  end

  describe "timeout/1" do
    test "aborts the search" do
      orphan = blk("tip", "p1", 1)
      {:request, "p1", s1} = ReorgSearch.start(orphan, local_work: 0)

      assert {:abort, :timeout, ^s1} = ReorgSearch.timeout(s1)
    end
  end
end
