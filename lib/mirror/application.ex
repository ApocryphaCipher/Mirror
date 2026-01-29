defmodule Mirror.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MirrorWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:mirror, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Mirror.PubSub},
      Mirror.Engine.Supervisor,
      Mirror.SessionStore,
      Mirror.Stats,
      # Start a worker by calling: Mirror.Worker.start_link(arg)
      # {Mirror.Worker, arg},
      # Start to serve requests, typically the last entry
      MirrorWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Mirror.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MirrorWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
