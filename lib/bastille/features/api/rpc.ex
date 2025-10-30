defmodule Bastille.Features.Api.RPC do
  @moduledoc """
  Bastille RPC endpoint (JSON-RPC 2.0 style)
  Let's you execute Bastille commands via POST /rpc (generate address, send transaction, etc.)
  """
  use Plug.Router

  alias Bastille.Features.Api.RPC.{
    CreateUnsignedTransaction,
    ExtractKeysForSigning,
    GenerateAddress,
    GetBalance,
    GetImmatureCoinbases,
    GetInfo,
    GetTransaction,
    SignTransaction,
    SubmitTransaction
  }

  plug :match
  plug :dispatch

  # POST /
  post "/" do
    with {:ok, body, _conn} <- Plug.Conn.read_body(conn),
         {:ok, req} <- Jason.decode(body),
         method when is_binary(method) <- req["method"],
         params when is_map(params) <- req["params"] do
      result =
        case method do
          "generate_address" ->
            GenerateAddress.call(params)
          "extract_keys_for_signing" ->
            ExtractKeysForSigning.call(params)
          "create_unsigned_transaction" ->
            CreateUnsignedTransaction.call(params)
          "sign_transaction" ->
            SignTransaction.call(params)
          "submit_transaction" ->
            SubmitTransaction.call(params)
          "get_balance" ->
            GetBalance.call(params)
          "get_immature_coinbases" ->
            GetImmatureCoinbases.call(params)
          "get_transaction" ->
            GetTransaction.call(params)
          "get_info" ->
            GetInfo.call(params)
          _ ->
            %{error: "Unknown method"}
        end
      resp = %{jsonrpc: "2.0", id: req["id"], result: result}
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(resp))
    else
      _ ->
        resp = %{jsonrpc: "2.0", error: "Invalid request"}
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(resp))
    end
  end

  # Fallback
  match _ do
    send_resp(conn, 404, "Not found")
  end

  # Plug.Cowboy child spec
  def child_spec(_opts) do
    # Get configurable RPC port
    rpc_port = Application.get_env(:bastille, :rpc_port, 8332)

    Plug.Cowboy.child_spec(
      scheme: :http,
      plug: __MODULE__,
      options: [ip: {127, 0, 0, 1}, port: rpc_port] # Configurable Bastille RPC port
    )
  end
end
