defmodule Hybridsocial.Config.Store do
  use GenServer

  alias Hybridsocial.Config.Setting
  alias Hybridsocial.Repo

  import Ecto.Query

  @table :hybridsocial_settings

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Get a setting value by key, returns nil if not found."
  def get(key) do
    case :ets.lookup(@table, key) do
      [{^key, value}] -> value
      [] -> nil
    end
  end

  @doc "Get a setting value by key, returns default if not found."
  def get(key, default) do
    case :ets.lookup(@table, key) do
      [{^key, value}] -> value
      [] -> default
    end
  end

  @doc "Set a setting value. Writes to DB and updates ETS."
  def set(key, value) do
    GenServer.call(__MODULE__, {:set, key, value})
  end

  @doc "Get all settings as a map of key => value."
  def all do
    @table
    |> :ets.tab2list()
    |> Map.new()
  end

  @doc "Get all settings for a given category as a map of key => value."
  def all(category) do
    settings =
      from(s in Setting, where: s.category == ^category)
      |> Repo.all()

    Map.new(settings, fn s -> {s.key, s.value["value"]} end)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    load_settings()
    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:set, key, value}, _from, state) do
    result = upsert_setting(key, value)

    case result do
      {:ok, _setting} ->
        :ets.insert(@table, {key, value})
        {:reply, :ok, state}

      {:error, changeset} ->
        {:reply, {:error, changeset}, state}
    end
  end

  defp load_settings do
    settings = Repo.all(Setting)

    Enum.each(settings, fn setting ->
      :ets.insert(@table, {setting.key, setting.value["value"]})
    end)
  end

  defp upsert_setting(key, value) do
    wrapped_value = %{"value" => value}

    case Repo.get(Setting, key) do
      nil ->
        %Setting{}
        |> Setting.changeset(%{key: key, value: wrapped_value})
        |> Repo.insert()

      existing ->
        existing
        |> Setting.changeset(%{value: wrapped_value})
        |> Repo.update()
    end
  end
end
