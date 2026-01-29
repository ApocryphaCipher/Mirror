defmodule Mirror.Engine.Supervisor do
  @moduledoc """
  Supervisor for engine infrastructure.
  """

  use Supervisor

  @spec start_link(Keyword.t()) :: Supervisor.on_start()
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @impl true
  def init(:ok) do
    children = [
      Mirror.Engine.Registry,
      Mirror.Engine.SessionSupervisor
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
