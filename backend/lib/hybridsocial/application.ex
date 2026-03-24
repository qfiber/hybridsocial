defmodule Hybridsocial.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    env = Application.get_env(:hybridsocial, :env)

    children =
      [
        HybridsocialWeb.Telemetry,
        Hybridsocial.Repo,
        {DNSCluster, query: Application.get_env(:hybridsocial, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Hybridsocial.PubSub},
        {Task.Supervisor, name: Hybridsocial.Federation.DeliveryTaskSupervisor}
      ] ++
        if(env != :test,
          do: [
            # Valkey cache pool (requires Redis/Valkey)
            Hybridsocial.Cache,
            # Runtime config from DB
            Hybridsocial.Config.Store,
            # NATS connection + JetStream setup
            Hybridsocial.Nats,
            Hybridsocial.Nats.Setup,
            # NATS consumers
            Hybridsocial.Federation.NatsDeliveryConsumer,
            Hybridsocial.Streaming.NatsBridge,
            Hybridsocial.Nats.JobConsumer,
            # Legacy workers (kept as fallback + non-NATS jobs)
            Hybridsocial.Content.ScheduledPostWorker,
            Hybridsocial.Trending.Worker,
            Hybridsocial.Search.IndexWorker,
            Hybridsocial.Feeds.SignalWorker
          ],
          else: []
        ) ++
        [
          HybridsocialWeb.Endpoint
        ]

    opts = [strategy: :one_for_one, name: Hybridsocial.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    HybridsocialWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
