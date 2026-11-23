defmodule Hybridsocial.Notifications.DigestWorker do
  @moduledoc """
  Emails opted-in users a summary of their unread notifications (#318).
  Runs hourly (with a tick on boot).

  A user opts in with `users.preferences["notification_digest"]` set to
  `"daily"` or `"weekly"` (anything else, including unset, is off). A user is
  due once a full period has passed since `users.notification_digest_at`, the
  end of their last digest window. Each run claims the user by moving that
  stamp to now before sending, so a digest only ever covers unread
  notifications created since the previous one, and a user with nothing
  unread is stamped but not emailed.

  Suspended, deleted, unconfirmed and not-yet-approved accounts are skipped.
  The `notification_digest_enabled` setting turns digests off instance-wide.
  """
  use GenServer

  import Ecto.Query

  alias Hybridsocial.{Config, Emails, Mailer, Repo}
  alias Hybridsocial.Accounts.{Identity, User}
  alias Hybridsocial.Notifications.Notification

  require Logger

  @interval :timer.hours(1)
  @batch 200
  # A tick that lands a little early still counts, so a daily digest doesn't
  # slip an hour every day.
  @slack_seconds 600
  @periods %{"daily" => 86_400, "weekly" => 7 * 86_400}

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    send(self(), :tick)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:tick, state) do
    try do
      sent = run_once()
      if sent > 0, do: Logger.info("DigestWorker: sent #{sent} digest(s)")
    rescue
      e -> Logger.error("DigestWorker crashed: #{Exception.message(e)}")
    end

    Process.send_after(self(), :tick, @interval)
    {:noreply, state}
  end

  @doc "Runs one pass and returns how many digests were sent."
  def run_once(now \\ DateTime.utc_now()) do
    if enabled?(), do: run_batches(now, 0), else: 0
  end

  def enabled?, do: Config.get("notification_digest_enabled", true) in [true, "true", "1"]

  defp run_batches(now, sent) do
    users = due_users(now)
    sent = Enum.reduce(users, sent, fn user, acc -> acc + process(user, now) end)
    # Every user in a batch is stamped, so the next query starts past them.
    if length(users) == @batch, do: run_batches(now, sent), else: sent
  end

  defp due_users(now) do
    daily_cutoff = DateTime.add(now, @slack_seconds - @periods["daily"], :second)
    weekly_cutoff = DateTime.add(now, @slack_seconds - @periods["weekly"], :second)

    from(u in User,
      join: i in Identity,
      on: i.id == u.identity_id,
      where: fragment("?->>'notification_digest'", u.preferences) in ^Map.keys(@periods),
      where: not is_nil(u.confirmed_at),
      where: u.approval_required == false or not is_nil(u.approved_at),
      where: is_nil(i.suspended_at) and is_nil(i.deleted_at),
      where:
        is_nil(u.notification_digest_at) or
          (fragment("?->>'notification_digest'", u.preferences) == "daily" and
             u.notification_digest_at <= ^daily_cutoff) or
          (fragment("?->>'notification_digest'", u.preferences) == "weekly" and
             u.notification_digest_at <= ^weekly_cutoff),
      limit: @batch,
      preload: [identity: i]
    )
    |> Repo.all()
  end

  defp process(%User{} = user, now) do
    since =
      user.notification_digest_at ||
        DateTime.add(now, -@periods[user.preferences["notification_digest"]], :second)

    # Claim before sending: only the run that moves the stamp sends, so two
    # nodes ticking together can't both email the same window.
    if claim(user, now) do
      user.identity_id |> unread_between(since, now) |> deliver(user)
    else
      0
    end
  end

  defp claim(user, now) do
    {count, _} =
      from(u in User,
        where: u.identity_id == ^user.identity_id,
        where:
          fragment(
            "? IS NOT DISTINCT FROM ?",
            u.notification_digest_at,
            type(^user.notification_digest_at, :utc_datetime_usec)
          )
      )
      |> Repo.update_all(set: [notification_digest_at: now])

    count == 1
  end

  defp unread_between(identity_id, since, now) do
    from(n in Notification,
      where: n.recipient_id == ^identity_id and n.read == false,
      where: n.inserted_at > ^since and n.inserted_at <= ^now,
      select: %{type: n.type}
    )
    |> Repo.all()
  end

  defp deliver([], _user), do: 0

  defp deliver(_notifications, %User{email: email}) when email in [nil, ""], do: 0

  defp deliver(notifications, user) do
    case user |> Emails.notification_digest_email(notifications) |> Mailer.deliver() do
      {:ok, _} ->
        1

      {:error, reason} ->
        Logger.warning("DigestWorker: digest for #{user.identity_id} failed: #{inspect(reason)}")
        0
    end
  end
end
