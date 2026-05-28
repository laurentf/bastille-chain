defmodule Bastille.Features.Chain.CumulativeWorkTest do
  use ExUnit.Case, async: false

  alias Bastille.Features.Mining.Mining
  alias Bastille.Infrastructure.Storage.CubDB.Chain

  @moduletag :unit

  describe "Mining.work_for_difficulty/1" do
    test "is zero for genesis and positive + strictly increasing for real difficulties" do
      assert Mining.work_for_difficulty(0) == 0

      works = Enum.map([1, 2, 10, 100, 1000], &Mining.work_for_difficulty/1)

      assert Enum.all?(works, &(&1 > 0))
      assert works == Enum.sort(works)
      assert length(Enum.uniq(works)) == length(works)
    end
  end

  describe "cumulative work" do
    test "accumulates strictly over a sequence of blocks" do
      difficulties = [1, 1, 2, 2, 5]

      {cumulative, _total} =
        Enum.map_reduce(difficulties, 0, fn difficulty, acc ->
          work = acc + Mining.work_for_difficulty(difficulty)
          {work, work}
        end)

      assert length(cumulative) == 5
      assert cumulative == Enum.sort(cumulative)
      assert length(Enum.uniq(cumulative)) == 5
    end

    test "stores and retrieves cumulative work by block hash" do
      hash = :crypto.strong_rand_bytes(32)

      assert {:error, :not_found} = Chain.get_cumulative_work(hash)
      assert :ok = Chain.store_cumulative_work(hash, 123_456)
      assert {:ok, 123_456} = Chain.get_cumulative_work(hash)
    end
  end
end
