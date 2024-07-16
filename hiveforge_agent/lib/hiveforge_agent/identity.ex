defmodule HiveforgeAgent.AgentIdentity do
  use GenServer
  require Logger
  alias HiveforgeAgent.Auth

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    Logger.info("Initializing AgentIdentity")
    # Load configuration into persistent_term
    persistent_term_keys = Application.get_env(:hiveforge_agent, :persistent_term_keys, [])
    for key <- persistent_term_keys do
      value =
        Application.get_env(:hiveforge_agent, __MODULE__, [])
        |> Keyword.get(key)
      :persistent_term.put({__MODULE__, key}, value)
      Logger.debug("Set persistent term for #{key}: #{inspect(value)}")
    end

    # Authenticate and get JWT
    config = %{
      api_endpoint: :persistent_term.get({__MODULE__, :api_endpoint}),
      api_key: :persistent_term.get({__MODULE__, :agent_key})
    }

    Logger.debug("Authentication config: #{inspect(config)}")

    case Auth.authenticate(config) do
      {:ok, token} ->
        Logger.info("Successfully obtained JWT")
        :persistent_term.put({__MODULE__, :jwt}, token)
        {:ok, %{jwt: token}}

      {:error, reason} ->
        Logger.error("Authentication failed: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  def get_agent_id, do: :persistent_term.get({__MODULE__, :agent_id})
  def get_agent_key, do: :persistent_term.get({__MODULE__, :agent_key})

  def get_jwt do
    case :persistent_term.get({__MODULE__, :jwt}) do
      nil ->
        Logger.warn("JWT not found in persistent term")
        {:error, :jwt_not_available}
      jwt when is_binary(jwt) ->
        {:ok, jwt}
      other ->
        Logger.error("Unexpected JWT format: #{inspect(other)}")
        {:error, :invalid_jwt_format}
    end
  end

  def refresh_jwt do
    GenServer.call(__MODULE__, :refresh_jwt)
  end

  def handle_call(:refresh_jwt, _from, state) do
    config = %{
      api_endpoint: :persistent_term.get({__MODULE__, :api_endpoint}),
      api_key: :persistent_term.get({__MODULE__, :agent_key})
    }

    case Auth.authenticate(config) do
      {:ok, token} ->
        :persistent_term.put({__MODULE__, :jwt}, token)
        {:reply, {:ok, token}, %{state | jwt: token}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
end
