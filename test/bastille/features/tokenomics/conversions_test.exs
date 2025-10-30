defmodule Bastille.Features.Tokenomics.ConversionsFeatureTest do
  use ExUnit.Case, async: true

  alias Bastille.Features.Tokenomics.{Token, Conversions}

  @moduletag :unit

  test "format_bast and conversions are consistent" do
    one_bast = 100_000_000_000_000
    assert Token.format_bast(one_bast) == "1.00000000000000 BAST"
    assert Conversions.juillet_to_bast(one_bast) == 1.0
    assert Conversions.bast_to_juillet(1.0) == one_bast
  end
end

