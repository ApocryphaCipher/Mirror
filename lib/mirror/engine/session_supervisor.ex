defmodule Mirror.Engine.SessionSupervisor do
  @moduledoc """
  Dynamic supervisor for engine sessions.
  """

  use DynamicSupervisor

  @spec start_link(Keyword.t()) :: Supervisor.on_start()
  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @spec start_session(Keyword.t()) :: DynamicSupervisor.on_start_child()
  def start_session(opts) do
    DynamicSupervisor.start_child(__MODULE__, {Mirror.Engine.Session, opts})
  end

  @spec stop_session(pid() | term()) :: :ok | {:error, :not_found}
  def stop_session(pid) when is_pid(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end

  def stop_session(session_id) do
    case Mirror.Engine.Session.whereis(session_id) do
      nil -> {:error, :not_found}
      pid -> DynamicSupervisor.terminate_child(__MODULE__, pid)
    end
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
