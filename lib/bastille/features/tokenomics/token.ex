defmodule Bastille.Features.Tokenomics.Token do
  @moduledoc """
  Bastille Token Economics with Bastille Day decimals.

  🇫🇷 Thematic Design:
  - 14 decimal places (for July 14th - Bastille Day!)
  - Smallest unit: "juillet" (July in French)
  - Fixed reward: 1789 BAST per block (no max supply, like DOGE utility model)
  - No halving - predictable utility token economics
  """

  # Import tokenomics (burn temporarily disabled)
  alias Bastille.Features.Tokenomics.Conversions
  alias Bastille.Shared.Constants

  @type amount_bast :: float()
  @type amount_juillet :: non_neg_integer()

  @doc """
  Convert BAST to juillet (smallest unit).

  ## Examples
      iex> Bastille.Features.TransactionProcessing.Token.bast_to_juillet(1.0)
      100_000_000_000_000

      iex> Bastille.Features.TransactionProcessing.Token.bast_to_juillet(0.00000000000001)
      1

      iex> Bastille.Features.TransactionProcessing.Token.bast_to_juillet(50.25)
      5_025_000_000_000_000
  """
  @spec bast_to_juillet(amount_bast()) :: amount_juillet()
  def bast_to_juillet(bast_amount) when is_number(bast_amount) do
    Conversions.bast_to_juillet(bast_amount)
  end

  @doc """
  Convert juillet to BAST (human-readable).

  ## Examples
      iex> Bastille.Features.TransactionProcessing.Token.juillet_to_bast(100_000_000_000_000)
      1.0

      iex> Bastille.Features.TransactionProcessing.Token.juillet_to_bast(1)
      0.00000000000001

      iex> Bastille.Features.TransactionProcessing.Token.juillet_to_bast(5_025_000_000_000_000)
      50.25
  """
  @spec juillet_to_bast(amount_juillet()) :: amount_bast()
  def juillet_to_bast(juillet_amount) when is_integer(juillet_amount) do
    Conversions.juillet_to_bast(juillet_amount)
  end
  
  # Handle float amounts (convert to integer first)
  def juillet_to_bast(juillet_amount) when is_float(juillet_amount) do
    juillet_amount
    |> round()
    |> juillet_to_bast()
  end

  @doc """
  Format juillet amount as human-readable BAST string.

  ## Examples
      iex> Bastille.Features.TransactionProcessing.Token.format_bast(5_025_000_000_000_000)
      "50.25000000000000 BAST"

      iex> Bastille.Features.TransactionProcessing.Token.format_bast(1)
      "0.00000000000001 BAST"
  """
  @spec format_bast(amount_juillet()) :: String.t()
  def format_bast(juillet_amount) do
    bast_amount = juillet_to_bast(juillet_amount)
    Conversions.format_bast(bast_amount)
  end

  @doc """
  Parse BAST string to juillet amount.

  ## Examples
      iex> Bastille.Features.TransactionProcessing.Token.parse_bast("50.25 BAST")
      {:ok, 5_025_000_000_000_000}

      iex> Bastille.Features.TransactionProcessing.Token.parse_bast("1.0")
      {:ok, 100_000_000_000_000}

      iex> Bastille.Features.TransactionProcessing.Token.parse_bast("invalid")
      {:error, :invalid_format}
  """
  @spec parse_bast(String.t()) :: {:ok, amount_juillet()} | {:error, atom()}
  def parse_bast(bast_string) do
    cleaned = bast_string |> String.trim() |> String.replace(" BAST", "")

    case Float.parse(cleaned) do
      {amount, ""} -> {:ok, bast_to_juillet(amount)}
      _ -> {:error, :invalid_format}
    end
  end

  @doc """
  Calculate fixed block reward (1789 BAST per block).

  ## Examples
      iex> Bastille.Features.TransactionProcessing.Token.block_reward(0)
      178_900_000_000_000_000  # 1789 BAST in juillet

      iex> Bastille.Features.TransactionProcessing.Token.block_reward(1_000_000)
      178_900_000_000_000_000  # Always 1789 BAST (no halving)
  """
  @spec block_reward(non_neg_integer()) :: amount_juillet()
  def block_reward(_block_height), do: Constants.block_reward_juillet()

  @doc """
  Get total supply after given block height (no max limit).
  """
  @spec total_supply_at_block(non_neg_integer()) :: amount_juillet()
  def total_supply_at_block(block_height) do
    Constants.total_supply_at_block(block_height)
  end

  @doc """
  Get token economics information.
  """
  @spec economics_info() :: map()
  def economics_info do
    Constants.tokenomics_summary()
  end

  @doc """
  Validate that a juillet amount is valid.
  """
  @spec valid_amount?(any()) :: boolean()
  def valid_amount?(amount) when is_integer(amount) and amount >= 0, do: true
  def valid_amount?(_), do: false

  @doc """
  Calculate transaction fee based on data size and priority.
  """
  @spec calculate_fee(pos_integer(), atom()) :: amount_juillet()
  def calculate_fee(data_size_bytes, priority \\ :normal) do
    base_fee = 1000  # 1000 juillet base fee
    size_fee = data_size_bytes * 10  # 10 juillet per byte

    priority_multiplier = get_priority_multiplier(priority)

    trunc((base_fee + size_fee) * priority_multiplier)
  end

  # Pattern matching for priority multipliers
  defp get_priority_multiplier(:low), do: 0.5
  defp get_priority_multiplier(:normal), do: 1.0
  defp get_priority_multiplier(:high), do: 2.0
  defp get_priority_multiplier(:urgent), do: 5.0
  defp get_priority_multiplier(_unknown), do: 1.0  # Default to normal

  # Burn disabled for now
  @spec calculate_burn_amount(amount_juillet()) :: amount_juillet()
  def calculate_burn_amount(_fee_amount), do: 0

  @spec calculate_remaining_fee(amount_juillet()) :: amount_juillet()
  def calculate_remaining_fee(fee_amount), do: fee_amount

  @spec track_fee_burn(amount_juillet()) :: :ok
  def track_fee_burn(_), do: :ok

  @spec total_burned() :: amount_juillet()
  def total_burned, do: 0

  @spec burn_history(non_neg_integer()) :: [map()]
  def burn_history(_limit \\ 100), do: []

  # Public helper functions for compatibility

  @doc """
  Get the number of decimals used in the token system.
  """
  @spec decimals() :: non_neg_integer()
  def decimals, do: Constants.decimals()

  @doc """
  Get the smallest unit name.
  """
  @spec smallest_unit() :: String.t()
  def smallest_unit, do: "juillet"

  @doc """
  Get the token symbol.
  """
  @spec symbol() :: String.t()
  def symbol, do: "BAST"

  @doc """
  Get the fixed block reward in BAST.
  """
  @spec fixed_reward() :: float()
  def fixed_reward, do: Constants.block_reward_bast() * 1.0

  @doc """
  Get the fixed block reward in juillet.
  """
  @spec fixed_reward_juillet() :: amount_juillet()
  def fixed_reward_juillet, do: Constants.block_reward_juillet()

  @doc """
  Get the base transaction fee in juillet.
  """
  @spec base_fee() :: amount_juillet()
  def base_fee, do: 1000  # Updated base fee

  @doc """
  Calculate data fee based on data size.
  """
  @spec data_fee(binary()) :: amount_juillet()
  def data_fee(data) when is_binary(data) do
    byte_size(data) * 10  # 10 juillet per byte
  end

  @doc """
  Calculate total transaction fee.
  """
  @spec transaction_fee(binary()) :: amount_juillet()
  def transaction_fee(data) do
    base_fee() + data_fee(data)
  end

  @doc """
  Get era name for a block height (simplified without halving).
  """
  @spec era_name(non_neg_integer()) :: String.t()
  def era_name(block_height) do
    case div(block_height, 100_000) do
      0 -> "Genesis Era"
      1 -> "First Republic"
      2 -> "Napoleonic Era"
      3 -> "Restoration Period"
      4 -> "July Revolution"
      _ -> "Modern Era"
    end
  end
end
