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
        {Task.Supervisor, name: Hybridsocial.Federation.DeliveryTaskSupervisor},
        {Task.Supervisor, name: Hybridsocial.TaskSupervisor},
        # Valkey cache pool — safe in test env because it's not transactional.
        # Tests that need isolation should use Cache.flush_pattern/1 in setup.
        Hybridsocial.Cache
      ] ++
        if(env != :test,
          do: [
            # Runtime config from DB — not started in test env because its
            # GenServer runs in its own process and would not see the test
            # sandbox connection. Tests that need it must start it themselves
            # via start_supervised!(Hybridsocial.Config.Store).
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
            Hybridsocial.Feeds.SignalWorker,
            # Keeps the global + trending-hashtag feed snapshots warm so
            # visitors skip the cold query + serialization cost.
            Hybridsocial.Feeds.PrewarmWorker,
            # Activity expiration cleanup
            Hybridsocial.Federation.ActivityExpirationWorker,
            # Per-user automatic post deletion (#254)
            Hybridsocial.Social.AutoDeleteWorker,
            # Prunes terminal federation_deliveries rows older than
            # federation_delivery_retention_days (default 30)
            Hybridsocial.Federation.DeliveryRetentionWorker,
            # Daily backstop that retires remote followers whose server
            # reports them gone (410 / webfinger-confirmed 404)
            Hybridsocial.Federation.DeadActorWorker,
            # Story expiry (hard-deletes expired ephemeral stories)
            Hybridsocial.Social.StoryExpiryWorker,
            # Timed posts (#261): deletes posts whose expires_at passed
            Hybridsocial.Social.PostExpiryWorker,
            # Recomputes account trust levels as accounts age (#67)
            Hybridsocial.Accounts.TrustLevelWorker,
            # Clears lapsed group sanctions (timed / partial bans). Cleanup
            # only — the authorization path already honours expiry at read
            # time, so a late tick can't keep anyone sanctioned.
            Hybridsocial.Groups.GroupSanctionExpiryWorker,
            # Media proxy cache TTL + LRU eviction
            Hybridsocial.Media.MediaProxyCacheWorker,
            # Hard-deletes media soft-deleted >7 days ago — covers
            # post-edit removals plus any other soft-delete path.
            Hybridsocial.Media.PurgeWorker,
            # Prunes encrypted backups older than backup_retention_days (default 30)
            Hybridsocial.Admin.BackupExpiryWorker,
            # Prunes resolved/dismissed reports older than report_retention_days (default 90)
            Hybridsocial.Moderation.ReportExpiryWorker,
            # Prunes approved/rejected appeals older than appeal_retention_days (default 90)
            Hybridsocial.Moderation.AppealExpiryWorker,
            # Reminds owners before, and (opt-in) permanently purges, expired takedowns
            Hybridsocial.Moderation.TakedownPurgeWorker,
            # Drains the moderation webhook delivery queue with exponential backoff
            Hybridsocial.Moderation.WebhookDeliveryWorker,
            # Drains the per-bot outbound webhook queue (same backoff curve)
            Hybridsocial.Bots.WebhookDeliveryWorker,
            # Polls Postgres / Valkey / NATS / OpenSearch every 60s and
            # writes samples for the admin dashboard charts.
            Hybridsocial.Metrics.Collector,
            # Daily prune of metrics rows past the retention window.
            Hybridsocial.Metrics.Retention
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
