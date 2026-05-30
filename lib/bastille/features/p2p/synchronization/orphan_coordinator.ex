defmodule Bastille.Features.P2P.Synchronization.OrphanCoordinator do
  @moduledoc """
  Decides what to do with a block that cannot be attached to the chain yet.

  Two situations, told apart by the orphan's height:

  - **Behind / IBD gap** (orphan far past our tip): we came online late or were
    offline. Trigger header-first catch-up (`Sync`) to back-fill the missing
    range forward.
  - **Competing fork** (orphan at our tip with a different parent): walk it back
    one parent at a time with `ReorgSearch` until the common ancestor, then hand
    the result to `Chain.reorganize/1`.

  Runs inside the `Node` GenServer process (reorg timeouts are armed with
  `self()` so they land back on `Node`) and threads the `Node` state struct.
  """

  require Logger

  alias Bastille.Features.Block.Block
  alias Bastille.Features.Chain.Chain
  alias Bastille.Features.Chain.ReorgSearch
  alias Bastille.Features.P2P.Messaging.Messages
  alias Bastille.Features.P2P.PeerManagement.{Node, Peer}
  alias Bastille.Features.P2P.Synchronization.Sync
  alias Bastille.Infrastructure.Storage.CubDB.Chain, as: ChainStorage

  @reorg_request_timeout_ms 10_000

  @doc "True when `block` is the parent the in-flight reorg search is waiting for."
  @spec reorg_awaited?(Block.t(), Node.t()) :: boolean()
  def reorg_awaited?(%Block{} = block, %Node{reorg_search: %ReorgSearch{awaiting: awaiting}}),
    do: block.hash == awaiting

  def reorg_awaited?(_block, _state), do: false

  @doc """
  Route an orphan: catch-up sync when we are behind, ReorgSearch on a tip fork.
  A reorg already in flight keeps being fed parents.
  """
  @spec handle_orphan(Block.t(), String.t(), non_neg_integer(), Node.t()) :: Node.t()
  def handle_orphan(%Block{} = orphan, address, port, %Node{reorg_search: %ReorgSearch{}} = state) do
    maybe_start_reorg_search(orphan, address, port, state)
  end

  def handle_orphan(%Block{} = orphan, address, port, %Node{} = state) do
    if orphan.header.index > Chain.get_height() + 1 do
      Sync.peer_height_discovered(orphan.header.index, peer_id(address, port))
      state
    else
      maybe_start_reorg_search(orphan, address, port, state)
    end
  end

  @doc "Apply a parent fetched during a reorg walk and advance/finish the search."
  @spec handle_reorg_parent(Block.t(), String.t(), non_neg_integer(), Node.t()) :: Node.t()
  def handle_reorg_parent(%Block{} = block, address, port, %Node{} = state) do
    state = cancel_reorg_timer(state)
    _ = Chain.add_block(block)
    state = %{state | blocks_seen: MapSet.put(state.blocks_seen, block.hash)}

    ancestor_work = known_ancestor_work(block.header.previous_hash)

    case ReorgSearch.advance(state.reorg_search, block, ancestor_work) do
      {:request, next, search} ->
        request_next_parent(next, search, address, port, state)

      {:found, %{better?: true} = result} ->
        log_reorg_found(result)
        # The switch (rollback + reapply) can apply up to MAX_REORG_DEPTH blocks;
        # run it off the Node process so message handling isn't blocked.
        Task.start(fn -> Chain.reorganize(result) end)
        clear_reorg_search(state)

      {:found, result} ->
        log_reorg_found(result)
        clear_reorg_search(state)

      {:abort, :max_depth_exceeded, search} ->
        Logger.warning(
          "❌ REORG SEARCH ABANDONED — fork deeper than max depth #{search.max_depth} (tip #{short_hash(search.tip_hash)})"
        )

        clear_reorg_search(state)

      {:ignore, _search} ->
        state
    end
  end

  @doc "Handle the per-parent reorg fetch timeout (delegated from Node's handle_info)."
  @spec handle_timeout(binary(), Node.t()) :: Node.t()
  def handle_timeout(
        tip_hash,
        %Node{reorg_search: %ReorgSearch{tip_hash: tip_hash} = search} = state
      ) do
    {:abort, :timeout, _} = ReorgSearch.timeout(search)

    Logger.warning(
      "❌ REORG SEARCH ABANDONED — parent fetch timed out after #{div(@reorg_request_timeout_ms, 1000)}s (tip #{short_hash(tip_hash)}, depth #{search.depth})"
    )

    %{state | reorg_search: nil, reorg_timeout_ref: nil}
  end

  def handle_timeout(_tip_hash, %Node{} = state), do: state

  # --- Reorg common-ancestor search (Sprint 4.3) -------------------------------

  defp maybe_start_reorg_search(
         %Block{} = orphan,
         address,
         port,
         %Node{reorg_search: %ReorgSearch{}} = state
       ) do
    request_parent_if_needed(address, port, orphan.header.previous_hash, state)
  end

  defp maybe_start_reorg_search(%Block{} = orphan, address, port, %Node{} = state) do
    {:request, parent_hash, search} = ReorgSearch.start(orphan, local_work: local_tip_work())
    log_reorg_initiated(orphan, search, address, port)

    case send_getdata_for(parent_hash, address, port, state) do
      :ok ->
        ref =
          Process.send_after(
            self(),
            {:reorg_search_timeout, orphan.hash},
            @reorg_request_timeout_ms
          )

        %{
          state
          | reorg_search: search,
            reorg_timeout_ref: ref,
            requested_blocks: MapSet.put(state.requested_blocks, parent_hash)
        }

      :error ->
        state
    end
  end

  # Fetch the next parent up the fork, arming the per-request timeout; abandon
  # the search if the peer is unreachable.
  defp request_next_parent(next, search, address, port, %Node{} = state) do
    case send_getdata_for(next, address, port, state) do
      :ok ->
        ref =
          Process.send_after(
            self(),
            {:reorg_search_timeout, search.tip_hash},
            @reorg_request_timeout_ms
          )

        %{
          state
          | reorg_search: search,
            reorg_timeout_ref: ref,
            requested_blocks: MapSet.put(state.requested_blocks, next)
        }

      :error ->
        Logger.warning(
          "❌ REORG SEARCH ABANDONED — peer unreachable for parent #{short_hash(next)}"
        )

        clear_reorg_search(state)
    end
  end

  defp request_parent_if_needed(address, port, parent_hash, %Node{} = state) do
    cond do
      not is_binary(parent_hash) ->
        state

      MapSet.member?(state.blocks_seen, parent_hash) ->
        state

      MapSet.member?(state.requested_blocks, parent_hash) ->
        state

      true ->
        case peer_pid(state, address, port) do
          nil ->
            :ok

          pid ->
            Logger.info("🧩 Requesting parent block #{short_hash(parent_hash)}")

            _ =
              Peer.send_message(
                pid,
                :getdata,
                Messages.getdata_message([{:block, parent_hash}])[:getdata]
              )
        end

        %{state | requested_blocks: MapSet.put(state.requested_blocks, parent_hash)}
    end
  end

  defp send_getdata_for(hash, address, port, %Node{} = state) do
    case peer_pid(state, address, port) do
      nil ->
        :error

      pid ->
        _ = Peer.send_message(pid, :getdata, Messages.getdata_message([{:block, hash}])[:getdata])
        :ok
    end
  end

  defp local_tip_work do
    with {:ok, {_height, head_hash}} <- ChainStorage.get_head(),
         {:ok, work} <- ChainStorage.get_cumulative_work(head_hash) do
      work
    else
      _ -> 0
    end
  end

  defp known_ancestor_work(hash) do
    case ChainStorage.get_cumulative_work(hash) do
      {:ok, work} -> work
      {:error, :not_found} -> nil
    end
  end

  defp cancel_reorg_timer(%Node{reorg_timeout_ref: nil} = state), do: state

  defp cancel_reorg_timer(%Node{reorg_timeout_ref: ref} = state) do
    _ = Process.cancel_timer(ref)
    %{state | reorg_timeout_ref: nil}
  end

  defp clear_reorg_search(%Node{} = state) do
    state |> cancel_reorg_timer() |> Map.put(:reorg_search, nil)
  end

  defp peer_id(address, port), do: "#{address}:#{port}"

  defp peer_pid(%Node{peers: peers}, address, port), do: Map.get(peers, peer_id(address, port))

  defp short_hash(hash) when is_binary(hash),
    do: hash |> Base.encode16(case: :lower) |> String.slice(0, 12)

  defp log_reorg_initiated(%Block{} = orphan, %ReorgSearch{} = search, address, port) do
    Logger.info("🔄 ═══════════════ REORG SEARCH INITIATED ═══════════════")
    Logger.info("   ├─ from_peer:    #{address}:#{port}")
    Logger.info("   ├─ tip_hash:     #{short_hash(orphan.hash)}")
    Logger.info("   ├─ tip_work:     #{search.acc_work}")
    Logger.info("   ├─ local_work:   #{search.local_work}")
    Logger.info("   └─ depth_so_far: #{search.depth}")
  end

  defp log_reorg_found(%{better?: true} = result) do
    Logger.info(
      "✅ REORG SEARCH SUCCESS — common ancestor #{short_hash(result.ancestor_hash)} found at depth #{result.depth}"
    )

    Logger.info("   ├─ alt_work:   #{result.alt_work} (wins)")
    Logger.info("   ├─ local_work: #{result.local_work}")

    Logger.info(
      "   └─ action:     triggering rollback + reapply of #{length(result.fork_chain)} block(s)"
    )
  end

  defp log_reorg_found(%{better?: false} = result) do
    Logger.info(
      "🛑 REORG SEARCH — common ancestor #{short_hash(result.ancestor_hash)} found at depth #{result.depth}, but alternative chain has less work"
    )

    Logger.info("   ├─ alt_work:   #{result.alt_work}")
    Logger.info("   └─ local_work: #{result.local_work} (kept)")
  end
end
