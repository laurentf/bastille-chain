defmodule Bastille.Features.Storage.BasicStorageFeatureTest do
  use ExUnit.Case, async: false

  alias Bastille.Infrastructure.Storage.CubDB.{Blocks, Chain, State, Index}

  @moduletag :integration

  setup do
    # Use Bastille.TestHelper to start services in proper order
    Bastille.TestHelper.start_test_services()

    on_exit(fn ->
      Bastille.TestHelper.stop_test_services()
    end)

    :ok
  end

  test "storages are initialized and accessible" do
    assert :ok == Index.index_block(<<0::256>>, "202501", 0)
    assert :ok == Chain.update_head(0, <<0::256>>)
    assert is_map(State.get_all_balances())
    assert {:error, :not_found} == Blocks.get_block(<<1::256>>)
  end
end
