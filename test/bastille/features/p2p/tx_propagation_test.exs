defmodule Bastille.Features.P2P.TxPropagationTest do
  use ExUnit.Case, async: false

  alias Bastille.Features.Transaction.{Mempool, Transaction}
  alias Bastille.Features.P2P.Messaging.{Codec, Messages}
  alias Bastille.Features.P2P.PeerManagement.Node

  # Touches the globally-supervised Node + Mempool; excluded from the default
  # run like the other integration tests. Run with `mix test --include integration`.
  @moduletag :integration

  defp addr do
    prefix = Application.get_env(:bastille, :address_prefix, "f789")
    prefix <> String.duplicate("a", 40)
  end

  test "a :tx message received by the Node lands in the local mempool" do
    tx =
      %Transaction{
        from: addr(),
        to: addr(),
        amount: 100_000,
        fee: 1_000,
        nonce: 0,
        timestamp: System.system_time(:second),
        data: "",
        signature: %{dilithium: <<1>>, falcon: <<2>>, sphincs: <<3>>},
        signature_type: :regular,
        hash: nil
      }
      |> Transaction.calculate_hash()

    # Serialize through the real wire codec so the payload is exactly what a
    # peer would deliver (string keys, signature decoded from bytes).
    {:ok, frame} = Codec.encode(:tx, Messages.tx_message(tx)[:tx])
    {:ok, {:tx, payload}} = Codec.decode(IO.iodata_to_binary(frame))

    node = Process.whereis(Node)
    assert is_pid(node)

    send(node, {:p2p_message, :tx, payload, "127.0.0.1", 9999})

    # get_status is a GenServer.call, so it returns only after the queued
    # :tx message has been handled — a clean synchronization barrier.
    _ = Node.get_status()

    assert %Transaction{hash: hash} = Mempool.get_transaction(tx.hash)
    assert hash == tx.hash
  end
end
