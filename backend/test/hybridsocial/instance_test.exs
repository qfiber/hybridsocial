defmodule Hybridsocial.InstanceTest do
  use Hybridsocial.DataCase, async: false

  alias Hybridsocial.Instance

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Hybridsocial.Repo, {:shared, self()})
    :ok
  end

  test "info returns instance data" do
    info = Instance.info()
    assert info.name == "HybridSocial"
    assert info.version == "0.1.0"
    assert is_map(info.stats)
    assert is_integer(info.stats.user_count)
  end

  test "nodeinfo returns 2.0 format" do
    ni = Instance.nodeinfo()
    assert ni.version == "2.0"
    assert ni.software.name == "hybridsocial"
    assert "activitypub" in ni.protocols
    assert is_integer(ni.usage.localPosts)
  end
end
