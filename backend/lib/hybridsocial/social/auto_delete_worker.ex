defmodule Hybridsocial.Social.AutoDeleteWorker do
  @moduledoc """
  Per-user automatic post deletion (#254).

  Every hour, for each local identity with `auto_delete_after_months` set,
  deletes its posts that are older than that many months. Only posts
  published after `auto_delete_enabled_at` are eligible, so posts that
  existed when the user turned the setting on are kept.

  Each post goes through `Posts.delete_post/2`, the same path as a manual
  delete: reply counts are fixed up, a federated `Delete` goes out, and the
  `post.deleted` webhook fires. Work is capped per run so a large backlog is
  spread over several hours instead of one burst of federation traffic.
  """
  use GenServer

  import Ecto.Query

  alias Hybridsocial.Accounts.Identity
  alias Hybridsocial.Repo
  alias Hybridsocial.Social.{Post, Posts}

  require Logger

  @interval :timer.hours(1)
  @per_identity_limit 200

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    schedule_tick()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:tick, state) do
    try do
      run()
    rescue
      e -> Logger.error("AutoDeleteWorker failed: #{Exception.message(e)}")
    end

    schedule_tick()
    {:noreply, state}
  end

  defp schedule_tick, do: Process.send_after(self(), :tick, @interval)

  @doc "Runs one sweep. Returns the number of posts deleted."
  def run(now \\ DateTime.utc_now()) do
    deleted =
      enabled_identities()
      |> Enum.map(&sweep_identity(&1, now))
      |> Enum.sum()

    if deleted > 0, do: Logger.info("AutoDeleteWorker: deleted #{deleted} posts")
    deleted
  end

  defp enabled_identities do
    Identity
    |> where(
      [i],
      not is_nil(i.auto_delete_after_months) and not is_nil(i.auto_delete_enabled_at) and
        i.is_local == true and is_nil(i.deleted_at)
    )
    |> select([i], %{
      id: i.id,
      months: i.auto_delete_after_months,
      enabled_at: i.auto_delete_enabled_at
    })
    |> Repo.all()
  end

  defp sweep_identity(%{id: id, months: months, enabled_at: enabled_at}, now) do
    cutoff = DateTime.shift(now, month: -months)

    Post
    |> where(
      [p],
      p.identity_id == ^id and is_nil(p.deleted_at) and not is_nil(p.published_at) and
        p.published_at >= ^enabled_at and p.published_at < ^cutoff
    )
    |> order_by([p], asc: p.published_at)
    |> limit(@per_identity_limit)
    |> select([p], p.id)
    |> Repo.all()
    |> Enum.count(fn post_id -> match?({:ok, _}, Posts.delete_post(post_id, id)) end)
  end
end
