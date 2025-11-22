defmodule Bastille.Features.Transaction.MempoolTest do
  use ExUnit.Case, async: false  # Mempool is a singleton GenServer
  alias Bastille.Features.Transaction.Mempool
  alias Bastille.Features.Transaction.Transaction
  alias Bastille.Features.Tokenomics.Token

  @moduletag :unit

  setup do
    # Stop any existing mempool and start fresh with test configuration
    case Process.whereis(Mempool) do
      nil -> :ok  # Not running
      _pid ->
        try do
          GenServer.stop(Mempool)
        catch
          :exit, _ -> :ok  # Process already dead
        end
    end

    start_test_mempool()

    on_exit(fn ->
      # Safe cleanup: only stop if process is alive
      case Process.whereis(Mempool) do
        nil -> :ok  # Already stopped
        _pid ->
          try do
            GenServer.stop(Mempool)
          catch
            :exit, _ -> :ok  # Process already dead, that's fine
          end
      end
    end)

    :ok
  end

  describe "mempool basic functionality" do
    test "starts with empty mempool" do
      assert Mempool.size() == 0
      assert Mempool.all_transactions() == []
    end

    test "mempool responds to API calls" do
      assert is_integer(Mempool.size())
      assert is_list(Mempool.all_transactions())
      assert is_list(Mempool.get_transactions())
    end

    test "can clear mempool" do
      assert Mempool.clear() == :ok
      assert Mempool.size() == 0
    end
  end

  describe "simple transaction addition" do
    test "can add a valid transaction" do
      tx = create_test_transaction([
        from: "f789" <> String.duplicate("1", 40),
        to: "f789" <> String.duplicate("2", 40),
        nonce: 100
      ])

      result = Mempool.add_transaction(tx)
      assert result == :ok
      assert Mempool.size() == 1
    end

    test "can retrieve added transaction" do
      tx = create_test_transaction([
        from: "f789" <> String.duplicate("3", 40),
        to: "f789" <> String.duplicate("4", 40),
        nonce: 200
      ])

      assert Mempool.add_transaction(tx) == :ok

      transactions = Mempool.all_transactions()
      assert length(transactions) == 1
      [retrieved_tx] = transactions
      assert retrieved_tx.hash == tx.hash
    end

    test "can add multiple transactions" do
      tx1 = create_test_transaction([
        from: "f789" <> String.duplicate("5", 40),
        to: "f789" <> String.duplicate("6", 40),
        nonce: 300
      ])
      tx2 = create_test_transaction([
        from: "f789" <> String.duplicate("7", 40),
        to: "f789" <> String.duplicate("8", 40),
        nonce: 400
      ])

      assert Mempool.add_transaction(tx1) == :ok
      assert Mempool.add_transaction(tx2) == :ok
      assert Mempool.size() == 2
    end
  end

  describe "mempool transaction validation" do
    test "rejects transactions with insufficient fee" do
      # Create mempool with higher minimum fee
      assert GenServer.stop(Mempool) == :ok
      {:ok, _pid} = Mempool.start_link(min_fee: 5000000, skip_signature_validation: true, skip_chain_validation: true)

      tx = create_test_transaction([
        from: "f789" <> String.duplicate("d", 40),
        to: "f789" <> String.duplicate("f", 40),
        nonce: 500
      ])

      # Transaction fee should be less than 5000000
      assert tx.fee < 5000000
      result = Mempool.add_transaction(tx)
      assert match?({:error, :insufficient_fee}, result)
      assert Mempool.size() == 0
    end

    test "accepts transactions with sufficient fee" do
      tx = create_test_transaction([
        from: "f789" <> String.duplicate("1", 40),
        to: "f789" <> String.duplicate("2", 40),
        nonce: 600
      ])

      # Default mempool has min_fee: 1000, our transaction should have higher fee
      assert tx.fee >= 1000
      assert Mempool.add_transaction(tx) == :ok
      assert Mempool.size() == 1
    end

    test "rejects duplicate transactions" do
      tx = create_test_transaction([
        from: "f789" <> String.duplicate("a", 40),
        to: "f789" <> String.duplicate("b", 40),
        nonce: 700
      ])

      assert Mempool.add_transaction(tx) == :ok
      assert Mempool.size() == 1

      # Try to add the same transaction again
      result = Mempool.add_transaction(tx)
      assert match?({:error, :already_exists}, result)
      assert Mempool.size() == 1
    end
  end

  describe "mempool capacity and limits" do
    test "respects maximum mempool size" do
      # Create mempool with small max size
      GenServer.stop(Mempool)
      {:ok, _pid} = Mempool.start_link(max_size: 2, skip_signature_validation: true, skip_chain_validation: true)

      tx1 = create_test_transaction([from: "f789" <> String.duplicate("1", 40), to: "f789" <> String.duplicate("2", 40), nonce: 1])
      tx2 = create_test_transaction([from: "f789" <> String.duplicate("3", 40), to: "f789" <> String.duplicate("4", 40), nonce: 2])
      tx3 = create_test_transaction([from: "f789" <> String.duplicate("5", 40), to: "f789" <> String.duplicate("6", 40), nonce: 3])

      assert Mempool.add_transaction(tx1) == :ok
      assert Mempool.add_transaction(tx2) == :ok
      assert Mempool.size() == 2

      # Third transaction should be rejected
      result = Mempool.add_transaction(tx3)
      assert match?({:error, :mempool_full}, result)
      assert Mempool.size() == 2
    end

    test "can retrieve limited number of transactions" do
      # Add multiple transactions with proper hex addresses
      hex_pairs = [{"a", "b"}, {"c", "d"}, {"e", "f"}, {"a", "e"}, {"b", "f"}]
      txs = for {{from_hex, to_hex}, i} <- Enum.with_index(hex_pairs, 1) do
        from_addr = "f789" <> String.duplicate(from_hex, 40)
        to_addr = "f789" <> String.duplicate(to_hex, 40)
        create_test_transaction([
          from: from_addr,
          to: to_addr,
          nonce: 800 + i
        ])
      end

      results = Enum.map(txs, &Mempool.add_transaction/1)

      Enum.each(results, fn result ->
        assert result == :ok
      end)
      assert Mempool.size() == 5

      # Get limited results
      limited = Mempool.get_transactions(3)
      assert length(limited) == 3

      # Get all
      all = Mempool.get_transactions(10)
      assert length(all) == 5
    end
  end

  describe "mempool transaction removal" do
    test "can remove specific transactions" do
      tx1 = create_test_transaction([from: "f789" <> String.duplicate("a", 40), to: "f789" <> String.duplicate("b", 40), nonce: 901])
      tx2 = create_test_transaction([from: "f789" <> String.duplicate("c", 40), to: "f789" <> String.duplicate("d", 40), nonce: 902])
      tx3 = create_test_transaction([from: "f789" <> String.duplicate("e", 40), to: "f789" <> String.duplicate("f", 40), nonce: 903])

      Mempool.add_transaction(tx1)
      Mempool.add_transaction(tx2)
      Mempool.add_transaction(tx3)
      assert Mempool.size() == 3

      # Remove tx2
      Mempool.remove_transactions([tx2.hash])
      assert Mempool.size() == 2

      remaining = Mempool.all_transactions()
      remaining_hashes = Enum.map(remaining, & &1.hash)

      assert tx1.hash in remaining_hashes
      assert tx3.hash in remaining_hashes
      refute tx2.hash in remaining_hashes
    end

    test "can remove multiple transactions at once" do
      hex_chars = ["a", "b", "c", "d"]
      txs = for {hex_char, i} <- Enum.with_index(hex_chars, 1) do
        to_char = case hex_char do
          "a" -> "e"
          "b" -> "f"
          "c" -> "e"
          "d" -> "f"
        end
        create_test_transaction([
          from: "f789" <> String.duplicate(hex_char, 40),
          to: "f789" <> String.duplicate(to_char, 40),
          nonce: 950 + i
        ])
      end

      results = Enum.map(txs, &Mempool.add_transaction/1)
      Enum.each(results, fn result -> assert result == :ok end)
      assert Mempool.size() == 4

      # Remove first 2 transactions
      hashes_to_remove = Enum.take(txs, 2) |> Enum.map(& &1.hash)
      Mempool.remove_transactions(hashes_to_remove)

      assert Mempool.size() == 2

      remaining = Mempool.all_transactions()
      remaining_hashes = Enum.map(remaining, & &1.hash)

      for hash <- hashes_to_remove do
        refute hash in remaining_hashes
      end
    end
  end

  # Helper function - start with minimal valid transaction using proper hex addresses
  defp create_test_transaction(opts) do
    defaults = [
      from: "f789" <> String.duplicate("a", 40),  # f789 + 40 hex chars
      to: "f789" <> String.duplicate("b", 40),    # f789 + 40 hex chars
      amount: Token.bast_to_juillet(1.0),
      nonce: 1
    ]

    attrs = Keyword.merge(defaults, opts)
    Transaction.new(attrs)
  end

  defp start_test_mempool() do
    # Small delay to ensure cleanup
    Process.sleep(10)

    case Mempool.start_link(skip_signature_validation: true, skip_chain_validation: true) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, pid}} -> kill_and_start(pid)
    end
  end

  defp kill_and_start(pid) do
    Process.exit(pid, :kill)
    start_test_mempool()
  end
end
