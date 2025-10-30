defmodule Bastille.Infrastructure.Storage.CubDB.State do
  @moduledoc """
  Account state storage (state.cubdb).

  RocksDB-Compatible Design:
  - Namespaced keys (account balances, nonces, state roots, public keys)
  - Atomic batch updates for state transitions
  - Range queries for state iteration
  - Merkle tree compatible for state roots

  Stores:
  - Account balances: "bal:1789ABC..." → balance_in_juillet
  - Account nonces: "nonce:1789ABC..." → current_nonce
  - Public keys: "pubkey:1789ABC..." → %{dilithium: pub, falcon: pub, sphincs: pub}
  - State metadata: "meta:total_supply", "meta:total_burned"
  """

  use GenServer
  require Logger
  alias Bastille.Infrastructure.Storage.CubDB.Batch

  alias Bastille.Features.Tokenomics.Token

  defstruct [:state_db, :db_path]

  @typedoc """
  Map of post-quantum public keys for an address.
  Contains Dilithium2, Falcon512, and SPHINCS+ public keys.
  """
  @type public_keys_map :: %{
    dilithium: binary(),
    falcon: binary(),
    sphincs: binary()
  }

  # Key namespaces (RocksDB column family simulation)
  @balance_prefix "bal:"        # "bal:1789ABC..." → balance
  @nonce_prefix "nonce:"        # "nonce:1789ABC..." → nonce
  @pubkey_prefix "pubkey:"      # "pubkey:1789ABC..." → public_keys_map
  @metadata_prefix "meta:"      # "meta:total_supply", "meta:total_burned"

  @doc """
  Start the state storage.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get account balance.
  """
  @spec get_balance(String.t()) :: {:ok, Token.amount_juillet()} | {:error, :not_found}
  def get_balance(address) do
    GenServer.call(__MODULE__, {:get_balance, address})
  end

  @doc """
  Update account balance.
  """
  @spec update_balance(String.t(), Token.amount_juillet()) :: :ok | {:error, term()}
  def update_balance(address, new_balance) do
    GenServer.call(__MODULE__, {:update_balance, address, new_balance})
  end

  @doc """
  Get account nonce.
  """
  @spec get_nonce(String.t()) :: {:ok, non_neg_integer()} | {:error, :not_found}
  def get_nonce(address) do
    GenServer.call(__MODULE__, {:get_nonce, address})
  end

  @doc """
  Update account nonce.
  """
  @spec update_nonce(String.t(), non_neg_integer()) :: :ok | {:error, term()}
  def update_nonce(address, new_nonce) do
    GenServer.call(__MODULE__, {:update_nonce, address, new_nonce})
  end

  @doc """
  Store public keys for an address.
  """
  @spec store_public_keys(String.t(), public_keys_map()) :: :ok | {:error, term()}
  def store_public_keys(address, public_keys) do
    GenServer.call(__MODULE__, {:store_public_keys, address, public_keys})
  end

  @doc """
  Get public keys for an address.
  """
  @spec get_public_keys(String.t()) :: {:ok, public_keys_map()} | {:error, :not_found}
  def get_public_keys(address) do
    GenServer.call(__MODULE__, {:get_public_keys, address})
  end

  @doc """
  Apply state changes atomically (batch operation).
  Used for transaction processing to ensure consistency.
  """
  @type state_change :: {:balance, String.t(), Token.amount_juillet()} | {:nonce, String.t(), non_neg_integer()}
  @spec apply_state_changes([state_change()]) :: :ok | {:error, term()}
  def apply_state_changes(changes) do
    GenServer.call(__MODULE__, {:apply_state_changes, changes})
  end

  @doc """
  Get all account balances (for debugging/testing only).
  
  ⚠️  WARNING: This queries ALL accounts from disk - testing/debugging only!
      Use get_balance/1 for individual account queries in production.
  """
  @spec get_all_balances() :: %{String.t() => Token.amount_juillet()}
  def get_all_balances do
    GenServer.call(__MODULE__, :get_all_balances)
  end

  @doc """
  Get total circulating supply.
  """
  @spec get_total_supply() :: Token.amount_juillet()
  def get_total_supply do
    GenServer.call(__MODULE__, :get_total_supply)
  end

  @doc """
  Update total supply and burned amounts.
  """
  @spec update_supply_metadata(Token.amount_juillet(), Token.amount_juillet()) :: :ok
  def update_supply_metadata(total_supply, total_burned) do
    GenServer.call(__MODULE__, {:update_supply_metadata, total_supply, total_burned})
  end

  @doc """
  Get state statistics.
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  # GenServer Callbacks

  @impl true
  def init(opts) do
    db_path = Keyword.get(opts, :db_path, Bastille.Infrastructure.Storage.CubDB.Paths.state_path())
    File.mkdir_p!(Path.dirname(db_path))

    {:ok, state_db} = CubDB.start_link(data_dir: db_path)

    state = %__MODULE__{
      state_db: state_db,
      db_path: db_path
    }

    Logger.info("💰 State storage initialized at #{db_path}")
    {:ok, state}
  end

  @impl true
  def handle_call({:get_balance, address}, _from, state) when is_binary(address) do
    key = @balance_prefix <> address

    case CubDB.get(state.state_db, key) do
      nil -> {:reply, {:ok, 0}, state}  # Default balance is 0
      balance -> {:reply, {:ok, balance}, state}
    end
  end
  def handle_call({:get_balance, _invalid_address}, _from, state) do
    {:reply, {:error, :invalid_address}, state}
  end

  @impl true
  def handle_call({:update_balance, address, new_balance}, _from, state) do
    key = @balance_prefix <> address

    case CubDB.put(state.state_db, key, new_balance) do
      :ok -> {:reply, :ok, state}
      error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:get_nonce, address}, _from, state) when is_binary(address) do
    key = @nonce_prefix <> address

    case CubDB.get(state.state_db, key) do
      nil -> {:reply, {:ok, 0}, state}  # Default nonce is 0
      nonce -> {:reply, {:ok, nonce}, state}
    end
  end
  def handle_call({:get_nonce, _invalid_address}, _from, state) do
    {:reply, {:error, :invalid_address}, state}
  end

  @impl true
  def handle_call({:update_nonce, address, new_nonce}, _from, state) do
    key = @nonce_prefix <> address

    case CubDB.put(state.state_db, key, new_nonce) do
      :ok -> {:reply, :ok, state}
      error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:store_public_keys, address, public_keys}, _from, state) do
    key = @pubkey_prefix <> address
    case CubDB.put(state.state_db, key, public_keys) do
      :ok -> {:reply, :ok, state}
      error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:get_public_keys, address}, _from, state) do
    key = @pubkey_prefix <> address
    case CubDB.get(state.state_db, key) do
      nil -> {:reply, {:error, :not_found}, state}
      public_keys -> {:reply, {:ok, public_keys}, state}
    end
  end

  @impl true
  def handle_call({:apply_state_changes, changes}, _from, state) do
    # Atomic batch operation for state consistency
    operations = Enum.map(changes, fn
      {:balance, address, amount} ->
        {:put, @balance_prefix <> address, amount}
      {:nonce, address, nonce} ->
        {:put, @nonce_prefix <> address, nonce}
    end)

    case batch_write(state.state_db, operations) do
      :ok -> {:reply, :ok, state}
      error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:get_all_balances, _from, state) do
    balances = CubDB.select(state.state_db,
      min_key: @balance_prefix,
      max_key: @balance_prefix <> "\xFF"
    )
    |> Enum.map(fn {key, balance} ->
      address = String.replace_prefix(key, @balance_prefix, "")
      {address, balance}
    end)
    |> Enum.into(%{})

    {:reply, balances, state}
  end

  @impl true
  def handle_call(:get_total_supply, _from, state) do
    # Calculate total supply from all balances
    total = CubDB.select(state.state_db,
      min_key: @balance_prefix,
      max_key: @balance_prefix <> "\xFF"
    )
    |> Enum.reduce(0, fn {_key, balance}, acc -> acc + balance end)

    {:reply, total, state}
  end

  @impl true
  def handle_call({:update_supply_metadata, total_supply, total_burned}, _from, state) do
    operations = [
      {:put, @metadata_prefix <> "total_supply", total_supply},
      {:put, @metadata_prefix <> "total_burned", total_burned}
    ]

    case batch_write(state.state_db, operations) do
      :ok -> {:reply, :ok, state}
      error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    account_count = count_keys_with_prefix(state.state_db, @balance_prefix)
    total_supply = get_total_supply_sync(state.state_db)
    total_burned = CubDB.get(state.state_db, @metadata_prefix <> "total_burned") || 0

    stats = %{
      total_accounts: account_count,
      total_supply: total_supply,
      total_burned: total_burned,
      circulating_supply: total_supply - total_burned,
      storage_type: "account_state",
      db_path: state.db_path,
      namespaces: %{
        balances: @balance_prefix,
        nonces: @nonce_prefix,
        metadata: @metadata_prefix
      }
    }

    {:reply, stats, state}
  end

  # Private functions

  defp batch_write(db, operations) do
    Batch.write(db, operations)
  end

  defp count_keys_with_prefix(db, prefix) do
    CubDB.select(db, min_key: prefix, max_key: prefix <> "\xFF")
    |> Enum.count()
  rescue
    _ -> 0
  end

  defp get_total_supply_sync(db) do
    CubDB.select(db, min_key: @balance_prefix, max_key: @balance_prefix <> "\xFF")
    |> Enum.reduce(0, fn {_key, balance}, acc -> acc + balance end)
  rescue
    _ -> 0
  end
end
