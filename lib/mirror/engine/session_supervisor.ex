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

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
