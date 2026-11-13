defmodule HybridsocialWeb.MediaProxyControllerTest do
  # async: false: runtime config (Config.Store), UPLOADS_DIR and the Req
  # stub seam are all global.
  use HybridsocialWeb.ConnCase, async: false

  alias Hybridsocial.Config
  alias Hybridsocial.Media.MediaProxy

  @remote "https://media.example/files/cat.png"
  @body "PNG-LIKE-BYTES"

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Hybridsocial.Repo, {:shared, self()})
    start_supervised!(Hybridsocial.Config.Store)

    tmp =
      Path.join(System.tmp_dir!(), "hs_proxy_ctrl_test_#{:erlang.unique_integer([:positive])}")

    File.mkdir_p!(tmp)
    System.put_env("UPLOADS_DIR", tmp)

    Application.put_env(:hybridsocial, :media_proxy_req_options, plug: {Req.Test, __MODULE__})

    Req.Test.stub(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("image/png", nil)
      |> Plug.Conn.send_resp(200, @body)
    end)

    on_exit(fn ->
      Application.delete_env(:hybridsocial, :media_proxy_req_options)
      System.delete_env("UPLOADS_DIR")
      File.rm_rf!(tmp)
    end)

    Config.set("media_proxy_enabled", true)
    {:ok, tmp_dir: tmp}
  end

  defp proxy_path, do: @remote |> MediaProxy.url() |> URI.parse() |> Map.get(:path)

  defp tmp_files(tmp_dir) do
    case File.ls(Path.join([tmp_dir, "proxy_cache", ".tmp"])) do
      {:ok, files} -> files
      {:error, _} -> []
    end
  end

  test "with the cache disabled, serves the media instead of crashing", %{
    conn: conn,
    tmp_dir: tmp
  } do
    Config.set("media_proxy_cache_enabled", false)

    conn = get(conn, proxy_path())

    assert response(conn, 200) == @body
    assert [content_type | _] = get_resp_header(conn, "content-type")
    assert content_type =~ "image/png"
    # The uncached download is cleaned up once it's sent.
    assert tmp_files(tmp) == []
  end

  test "with the cache disabled, honours Range requests", %{conn: conn} do
    Config.set("media_proxy_cache_enabled", false)

    conn = conn |> put_req_header("range", "bytes=0-2") |> get(proxy_path())

    assert response(conn, 206) == binary_part(@body, 0, 3)
  end

  test "with the cache enabled, serves and then hits the cache", %{conn: conn} do
    Config.set("media_proxy_cache_enabled", true)

    assert response(get(conn, proxy_path()), 200) == @body

    # Second request is served from disk: an upstream call would now fail.
    Req.Test.stub(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 500, "upstream down") end)
    assert response(get(build_conn(), proxy_path()), 200) == @body
  end
end
