defmodule Hybridsocial.Cache do
  @moduledoc "Valkey-backed cache with automatic JSON serialization."

  @pool_size 5

  def child_spec(_opts) do
    url = Application.get_env(:hybridsocial, :valkey_url, "redis://localhost:6379")

    children =
      for i <- 0..(@pool_size - 1) do
        Supervisor.child_spec(
          {Redix, {url, [name: :"valkey_#{i}"]}},
          id: {Redix, i}
        )
      end

    %{
      id: __MODULE__,
      type: :supervisor,
      start:
        {Supervisor, :start_link,
         [children, [strategy: :one_for_one, name: Hybridsocial.Cache.Supervisor]]}
    }
  end

  def get(key) do
    case command(["GET", prefix(key)]) do
      {:ok, nil} -> nil
      {:ok, value} -> Jason.decode!(value)
      {:error, _} -> nil
    end
  end

  def set(key, value, ttl_seconds \\ 300) do
    json = Jason.encode!(value)
    command(["SETEX", prefix(key), to_string(ttl_seconds), json])
    :ok
  end

  def delete(key) do
    command(["DEL", prefix(key)])
    :ok
  end

  def increment(key, ttl_seconds \\ 60) do
    case command(["INCR", prefix(key)]) do
      {:ok, count} ->
        if count == 1, do: command(["EXPIRE", prefix(key), to_string(ttl_seconds)])
        {:ok, count}

      error ->
        error
    end
  end

  def exists?(key) do
    case command(["EXISTS", prefix(key)]) do
      {:ok, 1} -> true
      _ -> false
    end
  end

  def flush_pattern(pattern) do
    case command(["KEYS", prefix(pattern)]) do
      {:ok, keys} when keys != [] -> command(["DEL" | keys])
      _ -> :ok
    end
  end

  defp command(cmd) do
    idx = :erlang.phash2(self(), @pool_size)
    Redix.command(:"valkey_#{idx}", cmd)
  end

  defp prefix(key), do: "hs:#{key}"
end
