defmodule Bastille.Infrastructure.Storage.CubDB.Batch do
  @moduledoc """
  Utility module for atomic CubDB batch operations.

  Provides a clean interface for performing multiple put/delete operations
  atomically using CubDB's native batch functions.
  """

  @doc """
  Performs atomic batch operations on a CubDB database.

  Operations can be:
  - `{:put, key, value}` - Insert or update a key-value pair
  - `{:delete, key}` - Delete a key

  Uses CubDB's native atomic operations for optimal performance.

  ## Examples

      iex> operations = [
      ...>   {:put, "key1", "value1"},
      ...>   {:put, "key2", "value2"},
      ...>   {:delete, "old_key"}
      ...> ]
      iex> Bastille.Infrastructure.Storage.CubDB.Batch.write(db, operations)
      :ok
  """
  @spec write(pid(), list({:put | :delete, any(), any()})) :: :ok | {:error, any()}
  def write(db, operations) do
    # Use CubDB's native atomic operations with pattern matching
    operations |> split_operations() |> apply_batch(db)
  end

  # Pattern matching for different batch operation combinations
  defp apply_batch({[], []}, _db), do: :ok
  defp apply_batch({puts, []}, db), do: CubDB.put_multi(db, puts)
  defp apply_batch({[], deletes}, db), do: CubDB.delete_multi(db, deletes)
  defp apply_batch({puts, deletes}, db), do: CubDB.put_and_delete_multi(db, puts, deletes)

  # Split operations into puts and deletes for CubDB native functions
  defp split_operations(operations) do
    Enum.reduce(operations, {[], []}, fn
      {:put, key, value}, {puts, deletes} -> {[{key, value} | puts], deletes}
      {:delete, key}, {puts, deletes} -> {puts, [key | deletes]}
    end)
  end
end
