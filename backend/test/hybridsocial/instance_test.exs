defmodule Hybridsocial.InstanceTest do
  use Hybridsocial.DataCase, async: false

  alias Hybridsocial.Instance

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Hybridsocial.Repo, {:shared, self()})
    start_supervised!(Hybridsocial.Config.Store)
    :ok
  end

  test "info returns instance data" do
    info = Instance.info()
    assert info.title == "HybridSocial"
    assert info.version =~ "HybridSocial #{Hybridsocial.Instance.version()}"
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

  test "user_agent/0 names the software, the real version and this instance" do
    ua = Hybridsocial.Instance.user_agent()

    assert ua ==
             "HybridSocial/#{Hybridsocial.Instance.version()} (+#{HybridsocialWeb.Endpoint.url()})"

    assert Hybridsocial.Instance.user_agent("MediaProxy") =~ ~r{^HybridSocial MediaProxy/}
    # Other HybridSocial instances detect previews by the "hybridsocial" substring.
    assert String.downcase(Hybridsocial.Instance.user_agent("LinkPreview")) =~ "hybridsocial"
  end
end
