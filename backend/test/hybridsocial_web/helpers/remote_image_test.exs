defmodule HybridsocialWeb.Helpers.RemoteImageTest do
  # async: false: runtime config (Config.Store) is global.
  use HybridsocialWeb.ConnCase, async: false

  alias Hybridsocial.Config
  alias HybridsocialWeb.Helpers.Account

  @remote "https://pbs.twimg.com/profile_banners/1/1500x500"

  setup do
    start_supervised!(Hybridsocial.Config.Store)
    Config.set("media_proxy_enabled", true)
    :ok
  end

  defp proxied?(url), do: is_binary(url) and url =~ "/proxy/media/"

  describe "remote_image/1" do
    test "routes a remote image through the media proxy" do
      assert proxied?(Account.remote_image(@remote))
    end

    test "leaves our own, relative and missing URLs alone" do
      local = HybridsocialWeb.Endpoint.url() <> "/uploads/a.png"
      assert Account.remote_image(local) == local
      assert Account.remote_image("/images/default-avatar.svg") == "/images/default-avatar.svg"
      assert Account.remote_image(nil) == nil
    end

    test "is a no-op when the proxy is disabled" do
      Config.set("media_proxy_enabled", false)
      assert Account.remote_image(@remote) == @remote
    end
  end

  test "remote_emojis/1 proxies url and static_url, keeping keys and shape" do
    [s, a] =
      Account.remote_emojis([
        %{"shortcode" => "x", "url" => @remote, "static_url" => @remote},
        %{shortcode: "y", url: @remote}
      ])

    assert s["shortcode"] == "x" and proxied?(s["url"]) and proxied?(s["static_url"])
    assert a.shortcode == "y" and proxied?(a.url)
    assert Account.remote_emojis(nil) == []
  end

  # The bug report: a bird.makeup profile loaded its avatar and banner
  # straight from pbs.twimg.com.
  test "a remote profile's avatar and banner come back proxied", %{conn: conn} do
    remote =
      create_user("birdremote")
      |> Ecto.Changeset.change(
        is_local: false,
        ap_actor_url: "https://bird.makeup/users/birdremote",
        avatar_url: "https://pbs.twimg.com/profile_images/1/a.png",
        header_url: @remote
      )
      |> Hybridsocial.Repo.update!()

    viewer = create_user("viewer_ri")
    body = conn |> auth_conn(viewer) |> get("/api/v1/accounts/#{remote.id}") |> json_response(200)

    assert proxied?(body["avatar_url"]), inspect(body["avatar_url"])
    assert proxied?(body["header_url"]), inspect(body["header_url"])
    refute body["avatar_url"] =~ "pbs.twimg.com/profile_images"
  end
end
