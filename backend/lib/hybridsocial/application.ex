defmodule Hybridsocial.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        HybridsocialWeb.Telemetry,
        Hybridsocial.Repo,
        Hybridsocial.Cache,
        Hybridsocial.Config.Store,
        {DNSCluster, query: Application.get_env(:hybridsocial, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Hybridsocial.PubSub},
        {Task.Supervisor, name: Hybridsocial.Federation.DeliveryTaskSupervisor}
      ] ++
        if(Application.get_env(:hybridsocial, :env) != :test,
          do: [
            Hybridsocial.Federation.DeliveryWorker,
            Hybridsocial.Content.ScheduledPostWorker,
            Hybridsocial.Trending.Worker,
            Hybridsocial.Search.IndexWorker,
            Hybridsocial.Feeds.SignalWorker
          ],
          else: []
        ) ++
        [
          # Start to serve requests, typically the last entry
          HybridsocialWeb.Endpoint
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Hybridsocial.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    HybridsocialWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
