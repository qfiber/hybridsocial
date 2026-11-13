defmodule Hybridsocial.Config.Store do
  use GenServer

  alias Hybridsocial.Config.{Registry, Setting}
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
  rescue
    ArgumentError -> nil
  end

  @doc "Get a setting value by key, returns default if not found."
  def get(key, default) do
    case :ets.lookup(@table, key) do
      [{^key, value}] -> value
      [] -> default
    end
  rescue
    ArgumentError -> default
  end

  @doc """
  Set a setting value. Writes to DB and updates ETS.

  A registered key's value is typed through `Config.Registry.normalize/2`
  first, so `"800"` is stored as `800` for an integer setting. Values that
  don't cast are stored as given; strict validation is the caller's job
  (the admin settings API rejects them with a 422).
  """
  def set(key, value) do
    GenServer.call(__MODULE__, {:set, key, Registry.normalize(key, value)})
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
      # Rows saved as strings before the registry existed read back typed.
      value = Registry.normalize(setting.key, setting.value["value"])
      :ets.insert(@table, {setting.key, value})
    end)
  end

  defp upsert_setting(key, value) do
    wrapped_value = %{"value" => value}

    case Repo.get(Setting, key) do
      nil ->
        %Setting{}
        |> Setting.changeset(%{
          key: key,
          value: wrapped_value,
          category: category_for_key(key)
        })
        |> Repo.insert()

      existing ->
        existing
        |> Setting.changeset(%{value: wrapped_value})
        |> Repo.update()
    end
  end

  # Infer category from key prefix so newly-created settings land in
  # the right bucket instead of all defaulting to "general". The
  # admin UIs filter by category (tiers page wants category == "tiers",
  # etc.), so without this, values saved from those pages came back
  # empty on reload because the row existed but with the wrong
  # category.
  defp category_for_key("tier_" <> _), do: "tiers"
  defp category_for_key("theme_" <> _), do: "theme"
  defp category_for_key("email_" <> _), do: "email"
  defp category_for_key("app_" <> _), do: "apps"
  defp category_for_key("backup_" <> _), do: "backups"
  defp category_for_key("tiers_" <> _), do: "tiers"
  defp category_for_key("federation_" <> _), do: "federation"
  defp category_for_key(_), do: "general"
end
