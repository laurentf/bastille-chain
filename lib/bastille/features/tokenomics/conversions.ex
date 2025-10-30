defmodule Bastille.Features.Tokenomics.Conversions do
  @moduledoc """
  Utility functions for converting between BAST and juillet units.

  All conversions use the constants from `Bastille.Shared.Constants`.
  """

  alias Bastille.Shared.Constants

  @type amount_bast :: float()
  @type amount_juillet :: non_neg_integer()

  @doc """
  Convert BAST to juillet (smallest unit).

  ## Examples
      iex> Bastille.Features.Tokenomics.Conversions.bast_to_juillet(1.0)
      100_000_000_000_000

      iex> Bastille.Features.Tokenomics.Conversions.bast_to_juillet(0.00000000000001)
      1

      iex> Bastille.Features.Tokenomics.Conversions.bast_to_juillet(50.25)
      5_025_000_000_000_000
  """
  @spec bast_to_juillet(amount_bast()) :: amount_juillet()
  def bast_to_juillet(bast_amount) when is_number(bast_amount) do
    trunc(bast_amount * Constants.juillet_per_bast())
  end

  @doc """
  Convert juillet to BAST (human-readable).

  ## Examples
      iex> Bastille.Features.Tokenomics.Conversions.juillet_to_bast(100_000_000_000_000)
      1.0

      iex> Bastille.Features.Tokenomics.Conversions.juillet_to_bast(1)
      0.00000000000001
  """
  @spec juillet_to_bast(amount_juillet()) :: amount_bast()
  def juillet_to_bast(juillet_amount) when is_integer(juillet_amount) and juillet_amount >= 0 do
    juillet_amount / Constants.juillet_per_bast()
  end

  @doc """
  Format BAST amount for display with proper decimal places.

  ## Examples
      iex> Bastille.Features.Tokenomics.Conversions.format_bast(1.23456789012345)
      "1.23456789012345 BAST"

      iex> Bastille.Features.Tokenomics.Conversions.format_bast(1000.0)
      "1000.0 BAST"
  """
  @spec format_bast(amount_bast()) :: String.t()
  def format_bast(bast_amount) when is_number(bast_amount) do
    decimals = Constants.decimals()
    :erlang.float_to_binary(bast_amount, [{:decimals, decimals}]) <> " BAST"
  end

  @doc """
  Format juillet amount for display.

  ## Examples
      iex> Bastille.Features.Tokenomics.Conversions.format_juillet(100_000_000_000_000)
      "100,000,000,000,000 juillet"

      iex> Bastille.Features.Tokenomics.Conversions.format_juillet(1)
      "1 juillet"
  """
  @spec format_juillet(amount_juillet()) :: String.t()
  def format_juillet(juillet_amount) when is_integer(juillet_amount) and juillet_amount >= 0 do
    formatted = juillet_amount |> Integer.to_string() |> add_commas()
    formatted <> " juillet"
  end

  @doc """
  Convert and format any amount to the most readable unit.

  Uses BAST for large amounts, juillet for small amounts.
  """
  @spec format_smart(amount_juillet()) :: String.t()
  def format_smart(juillet_amount) do
    if juillet_amount >= Constants.juillet_per_bast() do
      juillet_amount |> juillet_to_bast() |> format_bast()
    else
      format_juillet(juillet_amount)
    end
  end

  @doc """
  Parse a string amount that could be in BAST or juillet.

  ## Examples
      iex> Bastille.Features.Tokenomics.Conversions.parse_amount("1.5")
      {:ok, 150_000_000_000_000}

      iex> Bastille.Features.Tokenomics.Conversions.parse_amount("1000000 juillet")
      {:ok, 1000000}

      iex> Bastille.Features.Tokenomics.Conversions.parse_amount("invalid")
      {:error, :invalid_amount}
  """
  @spec parse_amount(String.t()) :: {:ok, amount_juillet()} | {:error, atom()}
  def parse_amount(amount_str) when is_binary(amount_str) do
    amount_str = String.trim(amount_str)

    cond do
      String.ends_with?(amount_str, " juillet") ->
        # Parse as juillet directly
        juillet_str = String.replace_suffix(amount_str, " juillet", "")
        case parse_integer_with_commas(juillet_str) do
          {:ok, juillet} -> {:ok, juillet}
          :error -> {:error, :invalid_amount}
        end

      String.ends_with?(amount_str, " BAST") ->
        # Parse as BAST and convert
        bast_str = String.replace_suffix(amount_str, " BAST", "")
        case Float.parse(bast_str) do
          {bast, ""} -> {:ok, bast_to_juillet(bast)}
          _ -> {:error, :invalid_amount}
        end

      true ->
        # Try to parse as float (assume BAST)
        case Float.parse(amount_str) do
          {bast, ""} -> {:ok, bast_to_juillet(bast)}
          _ -> {:error, :invalid_amount}
        end
    end
  end

  # Private helper functions

  defp add_commas(number_str) do
    number_str
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  defp parse_integer_with_commas(str) do
    clean_str = String.replace(str, ",", "")
    case Integer.parse(clean_str) do
      {int, ""} -> {:ok, int}
      _ -> :error
    end
  end
end
