defmodule Mirror.SessionStore do
  @moduledoc """
  Simple ETS-backed store for per-session editor state.
  """

  use GenServer

  @table :mirror_sessions

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def get(session_id) do
    case :ets.lookup(@table, session_id) do
      [{^session_id, state}] -> state
      [] -> nil
    end
  end

  def put(session_id, state) do
    GenServer.call(__MODULE__, {:put, session_id, state, self()})
  end

  def update(session_id, fun) when is_function(fun, 1) do
    GenServer.call(__MODULE__, {:update, session_id, fun, self()})
  end

  def subscribe(session_id) do
    Phoenix.PubSub.subscribe(Mirror.PubSub, topic(session_id))
  end

  def unsubscribe(session_id) do
    Phoenix.PubSub.unsubscribe(Mirror.PubSub, topic(session_id))
  end

  defp topic(session_id), do: "mirror:session:#{session_id}"

  defp broadcast_update(session_id, state, sender) do
    Phoenix.PubSub.broadcast(
      Mirror.PubSub,
      topic(session_id),
      {:session_state_updated, session_id, state, sender}
    )
  end

  @impl true
  def init(state) do
    :ets.new(@table, [
      :named_table,
      :set,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    {:ok, state}
  end

  @impl true
  def handle_call({:put, session_id, new_state, sender}, _from, state) do
    :ets.insert(@table, {session_id, new_state})
    broadcast_update(session_id, new_state, sender)
    {:reply, :ok, state}
  end

  def handle_call({:update, session_id, fun, sender}, _from, state) do
    current = get(session_id) || %{}

    case fun.(current) do
      {:error, reason} ->
        {:reply, {:error, reason}, state}

      {new_state, result} ->
        :ets.insert(@table, {session_id, new_state})
        broadcast_update(session_id, new_state, sender)
        {:reply, {:ok, new_state, result}, state}

      new_state ->
        :ets.insert(@table, {session_id, new_state})
        broadcast_update(session_id, new_state, sender)
        {:reply, {:ok, new_state}, state}
    end
  end
end
