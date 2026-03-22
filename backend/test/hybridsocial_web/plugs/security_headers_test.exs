defmodule HybridsocialWeb.Plugs.SecurityHeadersTest do
  use HybridsocialWeb.ConnCase, async: true

  describe "security headers" do
    test "all security headers are present in responses", %{conn: conn} do
      # Hit a public endpoint to get a response with headers
      conn = get(conn, "/api/v1/auth/pow-challenge")

      assert get_resp_header(conn, "x-frame-options") == ["DENY"]
      assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
      assert get_resp_header(conn, "x-xss-protection") == ["0"]
      assert get_resp_header(conn, "referrer-policy") == ["strict-origin-when-cross-origin"]
      assert get_resp_header(conn, "permissions-policy") == ["camera=(), microphone=(), geolocation=()"]
      assert get_resp_header(conn, "strict-transport-security") == ["max-age=31536000; includeSubDomains"]

      [csp] = get_resp_header(conn, "content-security-policy")
      assert csp =~ "default-src 'none'"
      assert csp =~ "frame-ancestors 'none'"
      assert csp =~ "base-uri 'none'"
      assert csp =~ "form-action 'self'"
    end
  end
end
