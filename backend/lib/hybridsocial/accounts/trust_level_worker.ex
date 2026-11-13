defmodule Hybridsocial.Accounts.TrustLevelWorker do
  @moduledoc """
  Keeps stored trust levels current (#67).

  Promotion is mostly a matter of time passing (an account turns a day, a
  week, a month old), which no request triggers, so a sweep recomputes every
  local person below the top computed level whose level isn't pinned.

  The gates don't depend on this: a level 0 account that hits one is
  recomputed on the spot. The sweep keeps the level that profiles, the
  admin panel and `/me` show in step. The first sweep runs shortly after
  boot; the interval is `trust_sweep_interval_minutes` (default 60).
  """
  use GenServer

  import Ecto.Query

  alias Hybridsocial.Accounts.{Identity, Trust}
  alias Hybridsocial.Config
  alias Hybridsocial.Repo

  require Logger

  @first_run :timer.seconds(30)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    Process.send_after(self(), :tick, @first_run)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:tick, state) do
    try do
      case run() do
        0 -> :ok
        n -> Logger.info("TrustLevelWorker: updated #{n} trust levels")
      end
    rescue
      e -> Logger.error("TrustLevelWorker failed: #{Exception.message(e)}")
    end

    Process.send_after(self(), :tick, :timer.minutes(interval_minutes()))
    {:noreply, state}
  end

  @doc "Runs one sweep. Returns how many levels changed."
  def run do
    Identity
    |> where(
      [i],
      i.type == "user" and i.is_local == true and is_nil(i.deleted_at) and
        i.trust_level_locked == false and i.trust_level < ^Trust.max_computed_level()
    )
    |> Repo.all()
    |> Enum.count(fn identity ->
      case Trust.refresh_trust_level(identity) do
        {:ok, %Identity{trust_level: level}} -> level != identity.trust_level
        _ -> false
      end
    end)
  end

  defp interval_minutes do
    case Config.get("trust_sweep_interval_minutes", 60) do
      n when is_integer(n) and n > 0 ->
        n

      n when is_binary(n) ->
        case Integer.parse(n) do
          {int, ""} when int > 0 -> int
          _ -> 60
        end

      _ ->
        60
    end
  end
end
