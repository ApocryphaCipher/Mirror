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
    :ets.insert(@table, {session_id, state})
    :ok
  end

  def update(session_id, fun) when is_function(fun, 1) do
    state = get(session_id) || %{}
    new_state = fun.(state)
    put(session_id, new_state)
    {:ok, new_state}
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
end
