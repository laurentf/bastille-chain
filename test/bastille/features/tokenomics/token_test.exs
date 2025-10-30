defmodule Bastille.Features.Tokenomics.TokenFeatureTest do
  use ExUnit.Case, async: true

  alias Bastille.Features.Tokenomics.Token

  @moduletag :unit

  test "fixed block reward is 1789 BAST in juillet units" do
    expected = 178_900_000_000_000_000
    for h <- [0, 1, 100, 1_000] do
      assert Token.block_reward(h) == expected
    end
  end
end

