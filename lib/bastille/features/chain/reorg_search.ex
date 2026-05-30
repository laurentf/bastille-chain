defmodule Bastille.Features.Chain.ReorgSearch do
  @moduledoc """
  Common-ancestor search for chain reorganization (Sprint 4.3).

  When an orphan block arrives whose parent we don't have, it may be the tip
  of a competing chain. To decide whether that chain should replace ours we
  must walk it back, parent by parent (each fetched over P2P via `getdata`),
  until we reach a block we already know — the common ancestor / fork point.
  Only then can the alternative chain's total work be compared to ours.

  This module is the pure decision core of that walk. It holds no sockets and
  performs no IO: the `Node` drives it, doing the `getdata` requests, the
  storage lookups (is this parent known? what's its cumulative work?) and the
  per-request timer. Each transition returns the next *action* for the Node:

    * `{:request, hash, search}`  — fetch this parent next
    * `{:found, result}`          — common ancestor reached; `result` says
                                    whether the alternative chain wins
    * `{:abort, reason, search}`  — give up (`:max_depth_exceeded` | `:timeout`)
    * `{:ignore, search}`         — a block arrived that we weren't waiting for

  `fork_chain` is kept oldest-first (ancestor side first, orphan tip last), i.e.
  the exact order Sprint 4.4 will reapply it in.
  """

  alias Bastille.Features.Block.Block
  alias Bastille.Features.Mining.Mining

  @max_reorg_depth 100

  defstruct [
    :tip_hash,
    :awaiting,
    :local_work,
    fork_chain: [],
    acc_work: 0,
    depth: 0,
    max_depth: @max_reorg_depth
  ]

  @type t :: %__MODULE__{
          tip_hash: binary(),
          awaiting: binary(),
          local_work: non_neg_integer(),
          fork_chain: [Block.t()],
          acc_work: non_neg_integer(),
          depth: non_neg_integer(),
          max_depth: pos_integer()
        }

  @type result :: %{
          ancestor_hash: binary(),
          fork_chain: [Block.t()],
          alt_work: non_neg_integer(),
          local_work: non_neg_integer(),
          depth: pos_integer(),
          better?: boolean()
        }

  @doc "Maximum fork depth chased before giving up."
  @spec max_reorg_depth() :: pos_integer()
  def max_reorg_depth, do: @max_reorg_depth

  @doc """
  Begin a search from a freshly received orphan whose parent is unknown.

  `opts`:
    * `:local_work` (required) — cumulative work of our current tip, the bar the
      alternative chain must beat.
    * `:max_depth` — override the fork-depth limit (defaults to #{@max_reorg_depth}).

  Returns `{:request, parent_hash, search}`: the Node should `getdata` that parent.
  """
  @spec start(Block.t(), keyword()) :: {:request, binary(), t()}
  def start(%Block{} = orphan, opts) do
    search = %__MODULE__{
      tip_hash: orphan.hash,
      awaiting: orphan.header.previous_hash,
      local_work: Keyword.fetch!(opts, :local_work),
      fork_chain: [orphan],
      acc_work: Mining.work_for_difficulty(orphan.header.difficulty),
      depth: 0,
      max_depth: Keyword.get(opts, :max_depth, @max_reorg_depth)
    }

    {:request, orphan.header.previous_hash, search}
  end

  @doc """
  Feed a fetched parent block into the search.

  `ancestor_work` is the cumulative work of `parent`'s own parent **iff** that
  grandparent is a block we already know (the caller looks it up); otherwise
  `nil`. A non-nil value means we just reached the common ancestor.
  """
  @spec advance(t(), Block.t(), non_neg_integer() | nil) ::
          {:request, binary(), t()}
          | {:found, result()}
          | {:abort, :max_depth_exceeded, t()}
          | {:ignore, t()}
  def advance(%__MODULE__{awaiting: awaiting} = search, %Block{hash: hash}, _ancestor_work)
      when hash != awaiting do
    {:ignore, search}
  end

  def advance(%__MODULE__{} = search, %Block{} = parent, ancestor_work) do
    search = %{
      search
      | fork_chain: [parent | search.fork_chain],
        acc_work: search.acc_work + Mining.work_for_difficulty(parent.header.difficulty),
        depth: search.depth + 1
    }

    cond do
      is_integer(ancestor_work) ->
        alt_work = ancestor_work + search.acc_work

        {:found,
         %{
           ancestor_hash: parent.header.previous_hash,
           fork_chain: search.fork_chain,
           alt_work: alt_work,
           local_work: search.local_work,
           depth: search.depth,
           better?: alt_work > search.local_work
         }}

      search.depth >= search.max_depth ->
        {:abort, :max_depth_exceeded, search}

      true ->
        next = parent.header.previous_hash
        {:request, next, %{search | awaiting: next}}
    end
  end

  @doc "The awaited parent never arrived within the per-request window."
  @spec timeout(t()) :: {:abort, :timeout, t()}
  def timeout(%__MODULE__{} = search), do: {:abort, :timeout, search}
end
