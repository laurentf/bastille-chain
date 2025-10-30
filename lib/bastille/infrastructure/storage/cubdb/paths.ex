defmodule Bastille.Infrastructure.Storage.CubDB.Paths do
  @moduledoc """
  Storage path utilities for multi-node configurations.

  Handles dynamic path generation with optional node prefixes
  to enable multiple nodes running on the same machine.
  """

  @doc """
  Get the base storage path with optional node prefix.

  ## Examples

      # Default configuration
      iex> Bastille.Infrastructure.Storage.CubDB.Paths.base_path()
      "data/test"

      # With node prefix
      iex> Application.put_env(:bastille, :storage, [base_path: "data/test", node_prefix: "node1"])
      iex> Bastille.Infrastructure.Storage.CubDB.Paths.base_path()
      "data/test/node1"
  """
  @spec base_path() :: String.t()
  def base_path do
    config = Application.get_env(:bastille, :storage, [])
    base = Keyword.get(config, :base_path, "data/test")
    prefix = Keyword.get(config, :node_prefix)

    case prefix do
      nil -> base
      prefix when is_binary(prefix) -> Path.join(base, prefix)
      _ -> base
    end
  end

  @doc """
  Get path for blocks database.
  """
  @spec blocks_path() :: String.t()
  def blocks_path do
    base_path()
  end

  @doc """
  Get path for chain database.
  """
  @spec chain_path() :: String.t()
  def chain_path do
    Path.join(base_path(), "chain.cubdb")
  end

  @doc """
  Get path for state database.
  """
  @spec state_path() :: String.t()
  def state_path do
    Path.join(base_path(), "state.cubdb")
  end

  @doc """
  Get path for index database.
  """
  @spec index_path() :: String.t()
  def index_path do
    Path.join(base_path(), "index.cubdb")
  end

  @doc """
  Ensure all storage directories exist.
  """
  @spec ensure_directories() :: :ok
  def ensure_directories do
    base = base_path()
    File.mkdir_p!(base)
    :ok
  end

  @doc """
  Get node identifier for logging.
  """
  @spec node_id() :: String.t()
  def node_id do
    config = Application.get_env(:bastille, :storage, [])
    prefix = Keyword.get(config, :node_prefix)

    case prefix do
      nil -> "main"
      prefix -> prefix
    end
  end
end
