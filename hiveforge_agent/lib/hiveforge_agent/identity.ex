defmodule HiveforgeAgent.AgentIdentity do
  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    # Load configuration into persistent_term
    persistent_term_keys = Application.get_env(:hiveforge_agent, :persistent_term_keys, [])

    for key <- persistent_term_keys do
      value =
        Application.get_env(:hiveforge_agent, __MODULE__, [])
        |> Keyword.get(key)

      :persistent_term.put({__MODULE__, key}, value)
    end

    {:ok, %{}}
  end

  def get_agent_id do
    :persistent_term.get({__MODULE__, :agent_id})
  end

  def get_agent_key do
    :persistent_term.get({__MODULE__, :agent_key})
  end

  def generate_nonce do
    :crypto.strong_rand_bytes(16)
    |> Base.encode64()
  end

  def generate_transaction_key(nonce) do
    agent_key = get_agent_key()

    :crypto.hmac(:sha256, agent_key, "TRANSACTION" <> nonce)
    |> Base.encode64()
  end

  # Add this to your API calls
  def sign_request(data, nonce) do
    transaction_key = generate_transaction_key(nonce)

    signature =
      :crypto.hmac(:sha256, transaction_key, data)
      |> Base.encode64()

    {nonce, signature}
  end
end
