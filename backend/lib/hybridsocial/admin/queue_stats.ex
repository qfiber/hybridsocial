defmodule Hybridsocial.Admin.QueueStats do
  @moduledoc "Collect stats about background job processing."

  @doc "Get stats from NATS JetStream and Task supervisors."
  def get_stats do
    nats_stats = get_nats_stats()
    task_stats = get_task_stats()
    worker_stats = get_worker_stats()

    %{
      nats: nats_stats,
      tasks: task_stats,
      workers: worker_stats,
      system: system_stats()
    }
  end

  defp get_nats_stats do
    # Check NATS connectivity via the streaming bridge process
    bridge_alive = Process.whereis(Hybridsocial.Streaming.NatsBridge) != nil
    %{connected: bridge_alive}
  rescue
    _ -> %{connected: false}
  end

  defp get_task_stats do
    case Process.whereis(Hybridsocial.TaskSupervisor) do
      nil -> %{active: 0}
      pid ->
        %{active: Task.Supervisor.children(pid) |> length()}
    end
  rescue
    _ -> %{active: 0}
  end

  defp get_worker_stats do
    workers = [
      {"IndexWorker", Hybridsocial.Search.IndexWorker},
      {"SignalWorker", Hybridsocial.Feeds.SignalWorker},
      {"ExpirationWorker", Hybridsocial.Federation.ActivityExpirationWorker}
    ]

    Enum.map(workers, fn {name, mod} ->
      alive = Process.whereis(mod) != nil
      %{name: name, alive: alive}
    end)
  end

  defp system_stats do
    memory = :erlang.memory()
    %{
      uptime_seconds: div(:erlang.statistics(:wall_clock) |> elem(0), 1000),
      memory_total_mb: div(memory[:total], 1_048_576),
      memory_processes_mb: div(memory[:processes], 1_048_576),
      process_count: :erlang.system_info(:process_count),
      scheduler_count: :erlang.system_info(:schedulers_online)
    }
  end
end
