defmodule Bastille.Features.Api.RPC.GetInfo do
  @moduledoc """
  Handles the get_info RPC command.
  """

  def call(_params) do
    Bastille.get_info()
  end
end
