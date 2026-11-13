defmodule HybridsocialWeb.Plugs.DigestPlugContentDigestTest do
  # async: false: flips the global signature-check env.
  use HybridsocialWeb.ConnCase, async: false

  alias HybridsocialWeb.Plugs.DigestPlug

  @body ~s({"type":"Follow"})

  setup do
    prev = Application.get_env(:hybridsocial, :federation_signature_check, true)
    Application.put_env(:hybridsocial, :federation_signature_check, true)
    on_exit(fn -> Application.put_env(:hybridsocial, :federation_signature_check, prev) end)
    :ok
  end

  defp inbox_post(headers, raw_body \\ @body) do
    conn = Plug.Test.conn(:post, "/inbox", raw_body) |> Plug.Conn.assign(:raw_body, raw_body)
    Enum.reduce(headers, conn, fn {k, v}, c -> Plug.Conn.put_req_header(c, k, v) end)
  end

  defp digest(body), do: "sha-256=:#{Base.encode64(:crypto.hash(:sha256, body))}:"

  test "an RFC 9530 Content-Digest that matches the body passes" do
    conn = DigestPlug.call(inbox_post([{"content-digest", digest(@body)}]), [])
    refute conn.halted
  end

  test "a Content-Digest that doesn't match the body is a 401" do
    conn =
      DigestPlug.call(inbox_post([{"content-digest", digest(@body)}], @body <> "tampered"), [])

    assert conn.halted and conn.status == 401
  end

  test "neither Digest nor Content-Digest is still a 401" do
    conn = DigestPlug.call(inbox_post([]), [])
    assert conn.halted and conn.status == 401
  end
end
