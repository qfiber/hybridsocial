defmodule Hybridsocial.CacheTest do
  use ExUnit.Case, async: false

  alias Hybridsocial.Cache

  setup do
    Redix.command!(:"valkey_0", ["FLUSHDB"])
    :ok
  end

  describe "get/1 and set/2" do
    test "returns nil for missing key" do
      assert Cache.get("nonexistent") == nil
    end

    test "stores and retrieves a string value" do
      Cache.set("test:string", "hello")
      assert Cache.get("test:string") == "hello"
    end

    test "stores and retrieves a map value" do
      data = %{"name" => "Alice", "age" => 30}
      Cache.set("test:map", data)
      assert Cache.get("test:map") == data
    end

    test "stores and retrieves a list value" do
      data = [1, 2, 3]
      Cache.set("test:list", data)
      assert Cache.get("test:list") == data
    end
  end

  describe "set/3 with TTL" do
    test "key expires after TTL" do
      Cache.set("test:ttl", "ephemeral", 1)
      assert Cache.get("test:ttl") == "ephemeral"
      Process.sleep(1100)
      assert Cache.get("test:ttl") == nil
    end
  end

  describe "delete/1" do
    test "removes a key" do
      Cache.set("test:del", "value")
      assert Cache.get("test:del") == "value"
      Cache.delete("test:del")
      assert Cache.get("test:del") == nil
    end
  end

  describe "increment/1" do
    test "increments a counter" do
      assert {:ok, 1} = Cache.increment("test:counter")
      assert {:ok, 2} = Cache.increment("test:counter")
      assert {:ok, 3} = Cache.increment("test:counter")
    end

    test "counter expires after TTL" do
      Cache.increment("test:counter:ttl", 1)
      assert {:ok, 2} = Cache.increment("test:counter:ttl", 1)
      Process.sleep(1100)
      assert {:ok, 1} = Cache.increment("test:counter:ttl", 1)
    end
  end

  describe "exists?/1" do
    test "returns false for missing key" do
      refute Cache.exists?("test:missing")
    end

    test "returns true for existing key" do
      Cache.set("test:exists", "yes")
      assert Cache.exists?("test:exists")
    end
  end

  describe "flush_pattern/1" do
    test "deletes keys matching a pattern" do
      Cache.set("test:flush:a", 1)
      Cache.set("test:flush:b", 2)
      Cache.set("test:keep", 3)

      Cache.flush_pattern("test:flush:*")

      assert Cache.get("test:flush:a") == nil
      assert Cache.get("test:flush:b") == nil
      assert Cache.get("test:keep") == 3
    end
  end
end
