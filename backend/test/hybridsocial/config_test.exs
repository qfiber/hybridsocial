defmodule Hybridsocial.ConfigTest do
  use Hybridsocial.DataCase, async: false

  alias Hybridsocial.Config
  alias Hybridsocial.Config.Setting

  setup do
    # Allow the Config.Store GenServer to use our DB connection
    Ecto.Adapters.SQL.Sandbox.mode(Hybridsocial.Repo, {:shared, self()})

    # Clear ETS table before each test
    if :ets.whereis(:hybridsocial_settings) != :undefined do
      :ets.delete_all_objects(:hybridsocial_settings)
    end

    :ok
  end

  describe "get/1 and get/2" do
    test "returns nil for non-existent key" do
      assert Config.get("nonexistent") == nil
    end

    test "returns default for non-existent key" do
      assert Config.get("nonexistent", "fallback") == "fallback"
    end

    test "returns value after set" do
      :ok = Config.set("test_key", "test_value")
      assert Config.get("test_key") == "test_value"
    end
  end

  describe "set/2" do
    test "persists to database" do
      :ok = Config.set("db_test_key", "db_test_value")

      setting = Repo.get(Setting, "db_test_key")
      assert setting != nil
      assert setting.value == %{"value" => "db_test_value"}
    end

    test "updates ETS cache" do
      :ok = Config.set("ets_key", "first")
      assert Config.get("ets_key") == "first"

      :ok = Config.set("ets_key", "second")
      assert Config.get("ets_key") == "second"
    end

    test "handles integer values" do
      :ok = Config.set("int_key", 42)
      assert Config.get("int_key") == 42
    end

    test "handles boolean values" do
      :ok = Config.set("bool_key", true)
      assert Config.get("bool_key") == true
    end
  end

  describe "all/0" do
    test "returns all settings as a map" do
      :ok = Config.set("all_key_1", "val1")
      :ok = Config.set("all_key_2", "val2")

      result = Config.all()
      assert result["all_key_1"] == "val1"
      assert result["all_key_2"] == "val2"
    end
  end

  describe "all/1" do
    test "returns settings filtered by category" do
      Repo.insert!(%Setting{
        key: "cat_test_1",
        value: %{"value" => "v1"},
        type: "string",
        category: "test_category"
      })

      Repo.insert!(%Setting{
        key: "cat_test_2",
        value: %{"value" => "v2"},
        type: "string",
        category: "test_category"
      })

      Repo.insert!(%Setting{
        key: "cat_other",
        value: %{"value" => "v3"},
        type: "string",
        category: "other_category"
      })

      result = Config.all("test_category")
      assert result == %{"cat_test_1" => "v1", "cat_test_2" => "v2"}
    end
  end

  describe "convenience functions" do
    test "instance_name returns default" do
      assert Config.instance_name() == "HybridSocial"
    end

    test "instance_name returns set value" do
      :ok = Config.set("instance_name", "MyInstance")
      assert Config.instance_name() == "MyInstance"
    end

    test "registration_open? returns true by default" do
      assert Config.registration_open?() == true
    end

    test "federation_enabled? returns true by default" do
      assert Config.federation_enabled?() == true
    end
  end
end
